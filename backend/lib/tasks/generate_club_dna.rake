namespace :clubs do
  desc "Generate Literature DNA for every club that has at least one past read (runs synchronously — watch the tagged [dna #id] logs)"
  task generate_dna: :environment do
    cls = BookClub.joins(:book_reads)
      .where.not(id: BookClub.where.not(dna_generated_at: nil).select(:id))
      .where("book_reads.meetup_time < ?", Time.current)
      .distinct
    abort "No OTARI_API_KEY set" if ENV["OTARI_API_KEY"].blank?
    puts "Generating Literature DNA for #{cls.count} club(s)…"

    cls.each do |club|
      print "… #{club.name} (##{club.id}) "
      result = ClubLiteratureDna.new(club: club).generate!
      if result.dna
        club.update!(literature_dna: result.dna, dna_generated_at: Time.current)
        puts "✓ highlights=#{result.dna.dig('narrative', 'highlights').to_a.size}"
      else
        puts "skipped (no past reads)"
      end
    rescue OtariClient::Error => e
      puts "✗ #{e.message.to_s[0, 140]}"
      next
    end
  end
end
