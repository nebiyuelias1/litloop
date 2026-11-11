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
  # Structured AI-panel calls (difficulty estimates, question clustering) can
  # legitimately outlast the default 60s read timeout with large inputs.
  AI_PANEL_READ_TIMEOUT = 240

  # otari_called/token_usage meter the gateway call for OtariBudget: called
  # is true as soon as the gateway answered a chat request (even if the
  # sandbox then produced no verifiable chart — the call was still spent).
  Result = Struct.new(:dna, :model, :otari_called, :token_usage, keyword_init: true)

  def initialize(club:)
    @club = club
  end

  def generate!(model: nil)
    model ||= DEFAULT_MODEL
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @otari_called = false
    @token_usage = { "input_tokens" => 0, "output_tokens" => 0, "total_tokens" => 0 }

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

    # AI-assisted, clearly-labeled panels: difficulty estimates and question
    # clusters. Both are non-fatal — without them the verified panels stand
    # alone and the AI panels simply don't render.
    if (estimates = difficulty_estimates(dataset, model))
      result["estimates"] = estimates
      result["estimates_model"] = model
    end
    if (clusters = question_clusters(dataset, model))
      result["question_clusters"] = clusters
      result["question_clusters_model"] = model
    end

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    dna_log("done in #{elapsed.round(1)}s model=#{model} chart=#{chart ? "yes(#{chart['bytes']}B)" : "no"} " \
      "tokens=#{@token_usage['total_tokens']}")

    Result.new(dna: result, model: model, otari_called: @otari_called, token_usage: @token_usage)
  end

  private

  # ---- AI-assisted panels (labeled in the UI, non-fatal) --------------------

  # Narrative-complexity and language-difficulty estimates (1-10) per book.
  # These are OPINIONS, not database facts — the UI badges them as AI
  # estimates. Pages stay verified and come from the dataset regardless.
  DIFFICULTY_SCHEMA = {
    type: "object",
    properties: {
      books: {
        type: "array",
        items: {
          type: "object",
          properties: {
            title: { type: "string" },
            complexity: { type: "integer" },
            language_difficulty: { type: "integer" }
          },
          required: %w[title complexity language_difficulty],
          additionalProperties: false
        }
      }
    },
    required: %w[books],
    additionalProperties: false
  }.freeze

  def difficulty_estimates(dataset, model)
    books = (dataset["sequence"] || []).filter_map { |s| s["title"].presence }
    return nil if books.empty?

    list = books.uniq.first(20)
    response = OtariClient.new.chat_structured(
      model: model,
      name: "difficulty_estimates",
      schema: DIFFICULTY_SCHEMA,
      temperature: 0.0,
      read_timeout: AI_PANEL_READ_TIMEOUT,
      messages: [
        { role: "system", content: <<~PROMPT },
          You estimate how demanding books are for a reading club. Respond ONLY
          with the schema. For each book give:
          - complexity: narrative/structural complexity 1-10 (linear pulp = 1-3,
            layered literary fiction = 7-10)
          - language_difficulty: prose difficulty 1-10 for a fluent adult reader
            reading in the book's original language (plain modern prose = 1-3,
            archaic, dialectal or highly literary prose = 7-10)
          Judge from general literary knowledge of the title and author. Use the
          exact titles given; never add books.
        PROMPT
        { role: "user", content: list.join("\n") }
      ]
    )
    meter_call!(response)

    valid = response["books"].is_a?(Array) ? response["books"] : []
    estimates = {}
    valid.each do |entry|
      title = entry["title"].to_s
      complexity = clamp_score(entry["complexity"])
      language = clamp_score(entry["language_difficulty"])
      next if title.blank? || complexity.nil? || language.nil?

      estimates[title] = { "complexity" => complexity, "language" => language }
    end
    estimates if estimates.any?
  rescue OtariClient::Error, StandardError => e
    dna_log("difficulty estimates failed (non-fatal): #{e.class} #{e.message.to_s[0, 120]}")
    nil
  end

  # Organizes the club's verbatim discussion questions into recurring themes.
  # The model returns only cluster names + the question NUMBERS it assigns —
  # the verbatim texts are resolved locally from the numbered list, so the
  # board always shows the original database strings (the model cannot
  # paraphrase them) and the slow echo-the-full-text response is avoided.
  QUESTIONS_SCHEMA = {
    type: "object",
    properties: {
      clusters: {
        type: "array",
        maxItems: 8,
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            ids: { type: "array", items: { type: "integer" } }
          },
          required: %w[name ids],
          additionalProperties: false
        }
      }
    },
    required: %w[clusters],
    additionalProperties: false
  }.freeze

  def question_clusters(dataset, model)
    questions = (dataset["questions"] || []).map { |q| q["text"].to_s }.reject(&:blank?).uniq
    return nil if questions.size < 4

    indexed = questions.first(60)
    response = OtariClient.new.chat_structured(
      model: model,
      name: "question_clusters",
      schema: QUESTIONS_SCHEMA,
      temperature: 0.0,
      read_timeout: AI_PANEL_READ_TIMEOUT,
      messages: [
        { role: "system", content: <<~PROMPT },
          Group a book club's numbered discussion questions into at most 6
          recurring themes (identity, morality, freedom, belonging, power,
          memory...). Rules:
          - For each cluster return `name` (one or two words) and `ids`: the
            NUMBERS of the questions belonging to it, as integers.
          - Never restate question text — numbers only.
          - Every number 1..#{indexed.size} must appear in exactly one cluster.
        PROMPT
        { role: "user", content: indexed.each_with_index.map { |text, i| "#{i + 1}. #{text}" }.join("\n") }
      ]
    )
    meter_call!(response)

    claimed = {}
    clusters = (response["clusters"] || []).filter_map do |cluster|
      name = cluster["name"].to_s.strip.presence
      ids = Array(cluster["ids"]).map(&:to_i).select { |id| id.between?(1, indexed.size) && !claimed[id] }
      next if name.blank? || ids.empty?

      ids.each { |id| claimed[id] = true }
      { "name" => name, "questions" => ids.map { |id| indexed[id - 1] } }
    end
    # Anything the model left ungrouped still shows, clearly labeled.
    if clusters.size >= 2 && claimed.size < indexed.size
      leftover = (1..indexed.size).reject { |id| claimed[id] }.map { |id| indexed[id - 1] }
      clusters << { "name" => I18n.t("dna_questions_other", default: "Other"), "questions" => leftover }
    end
    clusters if clusters.size >= 2
  rescue OtariClient::Error, StandardError => e
    dna_log("question clustering failed (non-fatal): #{e.class} #{e.message.to_s[0, 120]}")
    nil
  end

  def clamp_score(value)
    score = value.to_i
    return nil if score < 1 || score > 10

    score
  end

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

    # The gateway answered, so a chargeable call was made — meter it even if
    # the sandbox below yields no chart.
    meter_call!(response)

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

  # Every successful gateway call in a DNA run (chart, difficulty estimates,
  # question clustering) is chargeable — accumulate its usage for the meter.
  def meter_call!(response)
    @otari_called = true
    usage = response["usage"] || {}
    @token_usage = {
      "input_tokens" => @token_usage["input_tokens"] + usage["prompt_tokens"].to_i,
      "output_tokens" => @token_usage["output_tokens"] + usage["completion_tokens"].to_i,
      "total_tokens" => @token_usage["total_tokens"] + usage["total_tokens"].to_i
    }
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
