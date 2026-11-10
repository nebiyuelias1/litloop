namespace :clubs do
  desc "Generate Literature DNA for every club that has at least one past read (runs synchronously — watch the tagged [dna #id] logs). FORCE=1 regenerates clubs that already have DNA."
  task generate_dna: :environment do
    force = ENV["FORCE"].present?
    scope = BookClub.joins(:book_reads)
      .where("book_reads.meetup_time < ?", Time.current)
      .distinct
    scope = scope.where.not(id: BookClub.where.not(dna_generated_at: nil).select(:id)) unless force
    abort "No OTARI_API_KEY set" if ENV["OTARI_API_KEY"].blank?
    puts "Generating Literature DNA for #{scope.count} club(s)…"

    scope.each do |club|
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
