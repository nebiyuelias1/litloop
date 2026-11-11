# frozen_string_literal: true

# Generates a book club's "Literature DNA" board.
#
# Every number displayed is computed deterministically in Ruby
# (ClubDnaCollector). The model's only role is VISUAL: it authors matplotlib
# code that runs in Otari's code-execution sandbox to draw the club chart,
# which is downloaded via the Files API and shipped as a data URI. A chart
# failure is non-fatal — the HTML/SVG charts on the page remain the
# fallback. Nothing the model says is ever rendered.
class ClubLiteratureDna
  DEFAULT_MODEL = BookMetadataEnricher::DEFAULT_MODEL
  FALLBACK_MODEL = BookMetadataEnricher::FALLBACK_MODEL

  MIN_PAST_READS = 1
  MAX_SANDBOX_SNIPPET = 4000
  MAX_CHART_BYTES = 2_000_000
  PNG_MAGIC = "\x89PNG\r\n".b
  CHART_CALL_READ_TIMEOUT = 180

  Result = Struct.new(:dna, keyword_init: true)

  def initialize(club:)
    @club = club
  end

  def generate!(model: nil)
    model ||= DEFAULT_MODEL
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    dataset = ClubDnaCollector.new(club: @club).collect!.data
    past = dataset.dig("reads", "past").to_i
    if past < MIN_PAST_READS
      dna_log("skipped: only #{past} past read(s)")
      return Result.new(dna: nil)
    end

    result = {
      "dataset" => dataset,
      "model" => model,
      "sandbox_calls" => [],
      "generated_at" => Time.current.iso8601
    }

    # The model draws; the app verifies and displays everything else.
    chart = render_chart(model: model, dataset: dataset)
    if chart
      result["sandbox_calls"] = chart.delete("sandbox_calls") || []
      result["charts"] = chart
    end

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    dna_log("done in #{elapsed.round(1)}s model=#{model} chart=#{chart ? "yes(#{chart['bytes']}B)" : "no"}")

    Result.new(dna: result)
  end

  private

  # The model authors its own matplotlib code and runs it in the gateway's
  # sandbox; the produced PNG is downloaded through the Files API and shipped
  # as a data URI in the DNA payload. Returns nil (never raises) when the
  # sandbox does not yield one verifiable image — the HTML charts remain.
  def render_chart(model:, dataset:)
    client = OtariClient.new
    response = client.chat(
      model: model,
      temperature: 0.0,
      tools: [ { type: "otari_code_execution" } ],
      read_timeout: CHART_CALL_READ_TIMEOUT,
      messages: [
        { role: "user", content: <<~PROMPT }
          This verified dataset describes a book club. Visualize its most
          compelling insight in ONE chart — for example reads per month
          (reading rhythm), composition of recurring themes, or books per
          country — your choice guided by what the data best shows.

          ```json
          #{dataset.to_json}
          ```

          In the sandbox: write matplotlib code that renders exactly one file
          named chart.png. Rules:
          - matplotlib.use("Agg") first; savefig("chart.png", bbox_inches="tight")
          - transparent=False, white facecolor, primary color #8c3130
          - figsize at most 6 inches wide, dpi at most 100
          - short labels; if a category name uses non-Latin script (Amharic),
            translate it to English yourself
          - no other files, no markdown fences, print nothing else
        PROMPT
      ]
    )

    calls = response["otari_tool_calls"] || []
    file_id = calls.flat_map { |c| c["file_ids"] || [] }.compact.first
    if file_id.blank?
      dna_log("chart skipped: sandbox produced no file")
      return nil
    end

    bytes = client.download_file(file_id).to_s
    valid = bytes.bytesize.between?(1024, MAX_CHART_BYTES) && bytes.b.byteslice(0, 4) == PNG_MAGIC.byteslice(0, 4).b
    unless valid
      dna_log("chart rejected: #{bytes.bytesize}B, not a sane PNG")
      return nil
    end

    dna_log("chart produced in sandbox: #{file_id[0, 20]}… (#{bytes.bytesize}B)")
    {
      "data_uri" => "data:image/png;base64,#{Base64.strict_encode64(bytes)}",
      "file_id" => file_id,
      "bytes" => bytes.bytesize,
      "model" => model,
      "code" => calls.map { |c| c["code"].to_s }.compact_blank.join("\n---\n")[0, MAX_SANDBOX_SNIPPET],
      "sandbox_calls" => sandbox_calls(response)
    }
  rescue OtariClient::Error, StandardError => e
    dna_log("chart failed (non-fatal): #{e.class} #{e.message.to_s[0, 120]}")
    nil
  end

  # The sandbox trail is the audit evidence: what code the model ran and what
  # its own prints said (kept in the payload for the admin panel).
  def sandbox_calls(response)
    (response["otari_tool_calls"] || []).filter_map do |call|
      next if call["code"].blank?

      {
        "code" => call["code"].to_s[0, MAX_SANDBOX_SNIPPET],
        "stdout" => call["stdout"].to_s[0, MAX_SANDBOX_SNIPPET],
        "exit_code" => call["exit_code"]
      }
    end
  end

  def dna_log(message)
    Rails.logger.tagged("[dna ##{@club.id}]") { |l| l.info(message) }
  end
end
