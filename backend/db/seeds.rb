# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.

if !Rails.env.production?
  puts "🌱 Seeding database for #{Rails.env} environment..."

  # Clear existing records in development to ensure clean & reproducible seeding
  puts "🧹 Cleaning database..."
  BookReadRsvp.destroy_all
  PollVote.destroy_all
  PollOption.destroy_all
  Poll.destroy_all
  DiscussionQuestion.destroy_all
  BookRead.destroy_all
  MembershipRequest.destroy_all
  BookClubMember.destroy_all
  BookClub.destroy_all
  BookTag.destroy_all
  Tag.destroy_all
  ReviewLike.destroy_all
  Review.destroy_all
  Rating.destroy_all
  Book.destroy_all

  # 1. Tags
  puts "🏷️ Creating Tags..."
  tag_names = %w[አማርኛ ፍቅር ታሪክ ባህል ህይወት ልቦና ፖለቲካ Fiction Non-Fiction Philosophy African\ Literature Sci-Fi]
  tags = tag_names.index_with { |name| Tag.find_or_create_by!(name: name) }

  # 2. Users
  puts "👥 Creating Users..."
  users_data = [
    { name: "Abebe Bikila", email: "abebe@example.com" },
    { name: "Kebede Michael", email: "kebede@example.com" },
    { name: "Tigist Haile", email: "tigist@example.com" },
    { name: "Martha Wolde", email: "martha@example.com" },
    { name: "Yonas Alemu", email: "yonas@example.com" },
    { name: "Helen Tadesse", email: "helen@example.com" },
    { name: "Samuel Gebre", email: "samuel@example.com" },
    { name: "Selamawit Assefa", email: "selam@example.com" }
  ]

  users = users_data.map do |udata|
    user = User.find_or_initialize_by(email: udata[:email])
    user.name = udata[:name]
    user.password = "password123"
    user.password_confirmation = "password123"
    user.confirmed_at = Time.current
    user.save!
    user
  end

  admin_user = users.first
  admin_user.update!(admin: true)

  # 3. Books (12 books)
  puts "📚 Creating Books..."
  books_data = [
    {
      title: "ፍቅር እስከ መቃብር",
      author: "ሐዲስ አለማየሁ",
      description: "በኢትዮጵያ ሥነ ልቦና ውስጥ ከፍተኛ ዋጋ ያለው መፅሀፍ ነው። የአንድ ወጣት ወንድና የአንዲት ወጣት ሴት ፍቅርን በኢትዮጵያዊ ህይወትና ባህላዊ ተነሳስተኝነት ይገልጻል።",
      published_at: Date.new(1968, 1, 1),
      language: "am",
      publisher: "Addis Ababa University Press",
      isbn: "9789994400010",
      cover_image: "https://images.unsplash.com/photo-1544947950-fa07a98d237f?auto=format&fit=crop&w=600&q=80",
      average_rating: 4.9,
      reviews_count: 120,
      tag_names: %w[አማርኛ ፍቅር ታሪክ ባህል]
    },
    {
      title: "ኦሮማይ",
      author: "በዓሉ ግርማ",
      description: "የ1980ዎቹ በውስጥ የኢትዮጵያ የመንግስት ሥርዓትና የሞት ዘመን ውስጥ የአንድ የቴሌቪዥን ዘጋቢ ታሪክ።",
      published_at: Date.new(1983, 1, 1),
      language: "am",
      publisher: "Kuraz Publishing Agency",
      isbn: "9789994400056",
      cover_image: "https://images.unsplash.com/photo-1512820790803-83ca734da794?auto=format&fit=crop&w=600&q=80",
      average_rating: 4.8,
      reviews_count: 95,
      tag_names: %w[አማርኛ ፖለቲካ ታሪክ]
    },
    {
      title: "የተቆለፈበት ቁልፍ",
      author: "ዶ/ር መህረት ደበበ",
      description: "ልዩ ታሪክ በውጭ ተተመው የተነሳ የማኅበረሰብ እና የጭንቀት ጉዳዮችን የሚያሳይ።",
      published_at: Date.new(1995, 1, 1),
      language: "am",
      publisher: "የኢትዮጵያ ዩኒቨርሲቲ ፕረስ",
      isbn: "9789994400063",
      cover_image: "https://images.unsplash.com/photo-1543002588-bfa74002ed7e?auto=format&fit=crop&w=600&q=80",
      average_rating: 4.5,
      reviews_count: 88,
      tag_names: %w[አማርኛ ህይወት ልቦና]
    },
    {
      title: "አልወለድም",
      author: "በዓሉ ግርማ",
      description: "ስለ ፍልስፍና፣ ነፃነት እና ማህበራዊ ፍትህ የሚያትት ድንቅ የኢትዮጵያ ልቦለድ መፅሐፍ።",
      published_at: Date.new(1974, 1, 1),
      language: "am",
      publisher: "Kuraz Publishing",
      isbn: "9789994400070",
      cover_image: "https://images.unsplash.com/photo-1497633762265-9d179a990aa6?auto=format&fit=crop&w=600&q=80",
      average_rating: 4.7,
      reviews_count: 64,
      tag_names: %w[አማርኛ ፖለቲካ]
    },
    {
      title: "Things Fall Apart",
      author: "Chinua Achebe",
      description: "A classic novel exploring pre-colonial life in Nigeria and the arrival of European colonizers in the late nineteenth century.",
      published_at: Date.new(1958, 6, 17),
      language: "en",
      publisher: "Heinemann",
      isbn: "9780385474542",
      cover_image: "https://images.unsplash.com/photo-1532012197267-da84d127e765?auto=format&fit=crop&w=600&q=80",
      average_rating: 4.6,
      reviews_count: 210,
      tag_names: [ "Fiction", "African Literature" ]
    },
    {
      title: "The Alchemist",
      author: "Paulo Coelho",
      description: "An inspiring fable about following your dreams, listening to your heart, and reading the omens scattered along life's path.",
      published_at: Date.new(1988, 1, 1),
      language: "en",
      publisher: "HarperOne",
      isbn: "9780062315007",
      cover_image: "https://images.unsplash.com/photo-1516979187457-637abb4f9353?auto=format&fit=crop&w=600&q=80",
      average_rating: 4.7,
      reviews_count: 350,
      tag_names: %w[Fiction Philosophy]
    },
    {
      title: "Atomic Habits",
      author: "James Clear",
      description: "An easy & proven way to build good habits & break bad ones, offering a proven framework for self-improvement every day.",
      published_at: Date.new(2018, 10, 16),
      language: "en",
      publisher: "Avery",
      isbn: "9780735211292",
      cover_image: "https://images.unsplash.com/photo-1589829085413-56de8ae18c73?auto=format&fit=crop&w=600&q=80",
      average_rating: 4.9,
      reviews_count: 500,
      tag_names: %w[Non-Fiction]
    },
    {
      title: "Sapiens: A Brief History of Humankind",
      author: "Yuval Noah Harari",
      description: "A groundbreaking narrative of humanity's creation and evolution that explores how biology and history have defined us.",
      published_at: Date.new(2014, 9, 4),
      language: "en",
      publisher: "Harper",
      isbn: "9780062316097",
      cover_image: "https://images.unsplash.com/photo-1457369804613-52c61a468e7d?auto=format&fit=crop&w=600&q=80",
      average_rating: 4.8,
      reviews_count: 420,
      tag_names: %w[Non-Fiction Philosophy]
    },
    {
      title: "1984",
      author: "George Orwell",
      description: "A dystopian social science fiction novel and cautionary tale about totalitarianism, mass surveillance, and repressive regimentation.",
      published_at: Date.new(1949, 6, 8),
      language: "en",
      publisher: "Secker & Warburg",
      isbn: "9780451524935",
      cover_image: "https://images.unsplash.com/photo-1541963463532-d68292c34b19?auto=format&fit=crop&w=600&q=80",
      average_rating: 4.7,
      reviews_count: 610,
      tag_names: %w[Fiction Sci-Fi]
    },
    {
      title: "የቀን መሐሪ",
      author: "ሐዲስ አለማየሁ",
      description: "የማህበራዊና ባህላዊ ሁነቶችን የሚዳስስ ድንቅ የኢትዮጵያ ስነ ጽሁፍ ውጤት።",
      published_at: Date.new(1970, 1, 1),
      language: "am",
      publisher: "Kuraz Agency",
      isbn: "9789994400087",
      cover_image: "https://images.unsplash.com/photo-1476275466078-4007374efbbe?auto=format&fit=crop&w=600&q=80",
      average_rating: 4.3,
      reviews_count: 35,
      tag_names: %w[አማርኛ ታሪክ]
    },
    {
      title: "Dune",
      author: "Frank Herbert",
      description: "Set on the desert planet Arrakis, Dune is the story of the boy Paul Atreides, heir to a noble family in a interstellar empire.",
      published_at: Date.new(1965, 8, 1),
      language: "en",
      publisher: "Chilton Books",
      isbn: "9780441172719",
      cover_image: "https://images.unsplash.com/photo-1506880018603-83d5b814b5a6?auto=format&fit=crop&w=600&q=80",
      average_rating: 4.8,
      reviews_count: 310,
      tag_names: %w[Fiction Sci-Fi]
    },
    {
      title: "The Death of Vivek Oji",
      author: "Akwaeke Emezi",
      description: "A deeply affecting, atmospheric novel about family, identity, and innocence set in southeastern Nigeria.",
      published_at: Date.new(2020, 8, 4),
      language: "en",
      publisher: "Riverhead Books",
      isbn: "9780525541608",
      cover_image: "https://images.unsplash.com/photo-1524995997946-a1c2e315a42f?auto=format&fit=crop&w=600&q=80",
      average_rating: 4.6,
      reviews_count: 140,
      tag_names: [ "Fiction", "African Literature" ]
    }
  ]

  created_books = books_data.map do |bdata|
    t_names = bdata.delete(:tag_names)
    book = Book.create!(bdata)
    book.tags = t_names.map { |tn| tags[tn] }
    book
  end

  # 4. Book Clubs (5 clubs)
  puts "🏛️ Creating Book Clubs..."
  clubs_data = [
    {
      name: "አዲስ አበባ መፅሐፍ ክለብ",
      description: "በአዲስ አበባ እና በዙሪያዋ ያሉ የመፅሐፍ ወዳጆች የሚገናኙበትና በኢትዮጵያ ስነ ጽሁፍ ላይ የሚወያዩበት ክለብ።",
      owner: users[0]
    },
    {
      name: "Habesha Readers Circle",
      description: "A community for literature enthusiasts across East Africa discussing contemporary African writing & historical classics.",
      owner: users[1]
    },
    {
      name: "African Classics Society",
      description: "Dedicated to exploring foundational novels and philosophical works by celebrated African authors.",
      owner: users[2]
    },
    {
      name: "Non-Fiction & Productivity Hub",
      description: "Weekly deep dives into habit building, personal finance, history, and science.",
      owner: users[3]
    },
    {
      name: "Addis Sci-Fi & Speculative Readers",
      description: "Exploring dystopian worlds, futuristic fiction, and speculative novels from around the globe.",
      owner: users[4]
    },
    {
      name: "Secret Addis Reading Room",
      description: "A private circle for seasoned members. Request access to join our slow-reading sessions.",
      owner: users[5],
      is_private: true,
      application_form_url: "https://forms.example.com/litloop-private-club"
    }
  ]

  created_clubs = clubs_data.map do |cdata|
    BookClub.create!(cdata)
  end

  # Add members to clubs (private club is handled separately below)
  created_clubs.first(5).each do |club|
    users.sample(4).each do |u|
      unless club.has_member?(u)
        club.book_club_members.create!(user: u, role: :member)
      end
    end
  end

  # Private club: exactly the owner (auto-admin) and one trusted member
  created_clubs[5].book_club_members.create!(user: users[6], role: :member) unless created_clubs[5].has_member?(users[6])

  # 5. Book Reads (scenario-based)
  # Each read targets a specific state the app must handle:
  #   :fresh_upcoming         - just announced: book set, only the host RSVP'd, no questions
  #   :few_discussions        - a handful of questions in mixed statuses (draft/approved/revealed)
  #   :full_with_waitlist     - going RSVPs == max_capacity, plus waitlisted & cancelled RSVPs
  #   :no_capacity            - max_capacity nil (unlimited), healthy turnout
  #   :ongoing_poll           - book undecided, poll ACTIVE and taking votes
  #   :expired_poll           - poll closed (end_date passed, not finalized), book not picked yet
  #   :finalized_poll_past    - past session whose poll was finalized; the winner was discussed
  #   :past_revealed          - past session with revealed questions (one edited, one translated)
  #   :past_drafts            - past session whose questions were never revealed (still drafts)
  #   :online_session         - upcoming online session, decent turnout
  #   :quiet_upcoming         - low turnout, single draft question
  #   :private_club_session   - session inside a private club
  puts "📖 Creating Book Reads (12 scenario sessions)..."
  meetup_locations = [
    "National Archive & Library Agency (NALA), Addis Ababa",
    "Tomoca Coffee (Kazanchis Branch), Addis Ababa",
    "Fendika Cultural Center, Kazanchis",
    "Online via Google Meet",
    "Galani Coffee, Sarbet",
    "Urban Center, Meskel Square",
    "Kaldi's Coffee, Bole Medhanealem",
    "Bole Public Library"
  ]

  read_scenarios = [
    {
      key: :fresh_upcoming,
      book_club: created_clubs[0],
      book: created_books[0], # ፍቅር እስከ መቃብር
      host: users[0],
      meetup_time: 2.days.from_now + 4.hours,
      meetup_location: meetup_locations[0],
      max_capacity: 25
    },
    {
      key: :few_discussions,
      book_club: created_clubs[0],
      book: created_books[1], # ኦሮማይ
      host: users[1],
      meetup_time: 5.days.from_now + 2.hours,
      meetup_location: meetup_locations[1],
      max_capacity: 20
    },
    {
      key: :full_with_waitlist,
      book_club: created_clubs[1],
      book: created_books[4], # Things Fall Apart
      host: users[1],
      meetup_time: 7.days.from_now + 3.hours,
      meetup_location: meetup_locations[2],
      max_capacity: 4 # small on purpose so the session fills up and the waitlist kicks in
    },
    {
      key: :no_capacity,
      book_club: created_clubs[1],
      book: created_books[5], # The Alchemist
      host: users[2],
      meetup_time: 10.days.from_now + 1.hour,
      meetup_location: meetup_locations[3],
      max_capacity: nil # unlimited
    },
    {
      key: :ongoing_poll,
      book_club: created_clubs[2],
      book: nil, # book is undecided while the poll runs
      host: users[2],
      meetup_time: 12.days.from_now + 5.hours,
      meetup_location: meetup_locations[4],
      max_capacity: 18,
      poll_attributes: {
        text: "Which book should we read next?",
        description: "Voting is open — pick one of the three candidates.",
        end_date: 5.days.from_now,
        poll_options_attributes: [
          { content: created_books[11].title, book: created_books[11], suggested_by: users[3] }, # The Death of Vivek Oji
          { content: created_books[3].title, book: created_books[3], suggested_by: users[4] },   # አልወለድም
          { content: created_books[9].title, book: created_books[9], suggested_by: users[5] }    # የቀን መሐሪ
        ]
      }
    },
    {
      key: :expired_poll,
      book_club: created_clubs[3],
      book: nil, # voting ended but the host hasn't picked a book yet
      host: users[3],
      meetup_time: 14.days.from_now + 2.hours,
      meetup_location: meetup_locations[3],
      max_capacity: 40,
      poll_attributes: {
        text: "Pick our next deep-dive",
        end_date: 2.days.from_now, # backdated to the past after votes are cast below
        poll_options_attributes: [
          { content: created_books[6].title, book: created_books[6], suggested_by: users[4] }, # Atomic Habits
          { content: created_books[7].title, book: created_books[7], suggested_by: users[5] }  # Sapiens
        ]
      }
    },
    {
      key: :finalized_poll_past,
      book_club: created_clubs[3],
      book: created_books[6], # Atomic Habits — the poll's winning book
      host: users[3],
      meetup_time: 2.days.from_now + 2.hours, # backdated to the past below
      meetup_location: meetup_locations[5],
      max_capacity: 25,
      poll_attributes: {
        text: "Which book do you want to discuss in this session?",
        end_date: 3.days.from_now, # backdated + finalized after votes are cast below
        poll_options_attributes: [
          { content: created_books[6].title, book: created_books[6], suggested_by: users[4] }, # Atomic Habits
          { content: created_books[7].title, book: created_books[7], suggested_by: users[5] }  # Sapiens
        ]
      }
    },
    {
      key: :past_revealed,
      book_club: created_clubs[0],
      book: created_books[2], # የተቆለፈበት ቁልፍ
      host: users[0],
      meetup_time: 2.days.from_now + 2.hours, # backdated to the past below
      meetup_location: meetup_locations[7],
      max_capacity: 20
    },
    {
      key: :past_drafts,
      book_club: created_clubs[4],
      book: created_books[8], # 1984
      host: users[4],
      meetup_time: 2.days.from_now + 3.hours, # backdated to the past below
      meetup_location: meetup_locations[6],
      max_capacity: 20
    },
    {
      key: :online_session,
      book_club: created_clubs[4],
      book: created_books[10], # Dune
      host: users[5],
      meetup_time: 21.days.from_now + 4.hours,
      meetup_location: "Online via Google Meet",
      max_capacity: 30
    },
    {
      key: :quiet_upcoming,
      book_club: created_clubs[1],
      book: created_books[9], # የቀን መሐሪ
      host: users[1],
      meetup_time: 28.days.from_now + 3.hours,
      meetup_location: meetup_locations[1],
      max_capacity: 15
    },
    {
      key: :private_club_session,
      book_club: created_clubs[5], # Secret Addis Reading Room (private)
      book: created_books[7], # Sapiens
      host: users[5],
      meetup_time: 15.days.from_now + 6.hours,
      meetup_location: meetup_locations[0],
      max_capacity: 12
    }
  ]

  reads = {}
  read_scenarios.each do |rdata|
    key = rdata.delete(:key)
    reads[key] = BookRead.create!(rdata)
  end

  # Backdate the past sessions. meetup_time is validated against the past on
  # save, so reads are created with a future time and written directly
  # (update_columns skips validations and the calendar-invite callback).
  reads[:finalized_poll_past].update_columns(meetup_time: 2.weeks.ago + 3.hours)
  reads[:past_revealed].update_columns(meetup_time: 10.days.ago + 4.hours)
  reads[:past_drafts].update_columns(meetup_time: 3.weeks.ago + 2.hours)

  # 6. RSVPs (explicit per-session plan: going / waitlisted / cancelled)
  puts "🎟️ Creating RSVPs..."
  rsvp_plan = {
    fresh_upcoming:    { going: [ users[0] ] },
    few_discussions:   { going: [ users[1], users[2], users[3] ] },
    full_with_waitlist: { going: [ users[1], users[2], users[3], users[4] ], waitlisted: [ users[5], users[6] ], cancelled: [ users[7] ] },
    no_capacity:       { going: [ users[1], users[2], users[3], users[4], users[5] ] },
    ongoing_poll:      { going: [ users[2], users[3], users[5] ] },
    expired_poll:      { going: [ users[3], users[4], users[6] ] },
    finalized_poll_past: { going: [ users[3], users[4], users[5], users[6] ], cancelled: [ users[7] ] },
    past_revealed:     { going: [ users[0], users[1], users[2], users[3], users[4] ], cancelled: [ users[5] ] },
    past_drafts:       { going: [ users[4], users[5], users[6] ] },
    online_session:    { going: [ users[5], users[0], users[1], users[2], users[3] ] },
    quiet_upcoming:    { going: [ users[1], users[4] ] },
    private_club_session: { going: [ users[5], users[6] ] }
  }

  rsvp_plan.each do |key, plan|
    bread = reads[key]
    plan[:going].each do |u|
      BookReadRsvp.create!(book_read: bread, user: u, status: :going)
    end
    (plan[:waitlisted] || []).each do |u|
      BookReadRsvp.create!(book_read: bread, user: u, status: :waitlisted)
    end
    (plan[:cancelled] || []).each do |u|
      BookReadRsvp.create!(book_read: bread, user: u, status: :cancelled)
    end
  end

  # 7. Poll votes & poll states
  # Votes are cast while each poll is still active; expired/finalized states are
  # written afterwards (update_column skips the PollVote "poll must be active"
  # validation, mirroring how a real poll ages).
  puts "🗳️ Creating Poll Votes..."
  poll_vote_plan = {
    ongoing_poll: {
      0 => [ users[2], users[3], users[5] ], # The Death of Vivek Oji — current leader
      1 => [ users[4], users[6] ],           # አልወለድም
      2 => [ users[7] ]                      # የቀን መሐሪ
    },
    expired_poll: {
      0 => [ users[3], users[4], users[6], users[1] ], # Atomic Habits — clear winner, not yet picked
      1 => [ users[5], users[0] ]                      # Sapiens
    },
    finalized_poll_past: {
      0 => [ users[3], users[4], users[5], users[6], users[2] ], # Atomic Habits — won & became the read's book
      1 => [ users[0], users[7] ]                                # Sapiens
    }
  }

  poll_vote_plan.each do |key, votes_by_option|
    options = reads[key].poll.poll_options.order(:id).to_a
    votes_by_option.each do |option_index, voters|
      voters.each do |u|
        PollVote.create!(poll_option: options[option_index], user: u)
      end
    end
  end

  # Expired but not finalized: the voting window passed, host hasn't chosen yet
  reads[:expired_poll].poll.update_column(:end_date, 2.days.ago)
  # Finalized: the winner was recorded and the session already happened
  reads[:finalized_poll_past].poll.update_columns(end_date: 3.weeks.ago, finalized_at: 3.weeks.ago)

  # 8. Discussion questions (draft / approved / revealed, edited flag, translations)
  puts "❓ Creating Discussion Questions..."
  question_plan = {
    few_discussions: [
      { user: users[2], content: "ኦሮማይ በወቅቱ የፖለቲካ ሁኔታዎች ላይ ምን ያህል ትክክለኛ ነበር?", status: :draft },
      { user: users[3], content: "ግብረ አበረታዩና ተቃዋሚው የተገናኙበትን ግንኙነት እንዴት አየዋል?", status: :approved },
      { user: users[1], content: "በስደት ወቅት የተጻፈው መፅሐፍ ስለ ታማኝነትና ሞራል ምን ይናገራል?", status: :revealed }
    ],
    finalized_poll_past: [
      { user: users[3], content: "Which of the four laws of behaviour change was hardest to apply to your own routine?", status: :revealed },
      { user: users[4], content: "How do you balance identity-based habits with outcome-based goals?", status: :revealed, edited: true }
    ],
    past_revealed: [
      { user: users[1], content: "ወጣቱ ወደ ውጭ አገር ሲሄድ ከአገሩ ጋር ያለውን ግንኙነት እንዴት አይቷል?", status: :revealed, edited: true },
      { user: users[2], content: "የስደተኞች ጭንቀትና ተስፋ ስራሽ በዚህ መፅሐፍ ውስጥ እንዴት ተነግሯል?", status: :revealed },
      {
        user: users[0],
        content: "የመጨረሻው ምዕራፍ ስለ ነፃነት ያለው አስተያየት ምንድን ነው?",
        status: :revealed,
        translations: [
          { language_code: "ZH-HANT", content: "最後一章對自由的詮釋是什麼？" },
          { language_code: "PINYIN", content: "zuìhòu yī zhāng duì zìyóu de quánshì shì shénme?" }
        ]
      }
    ],
    past_drafts: [
      { user: users[5], content: "Was Winston's rebellion ever more than a personal act of defiance?", status: :draft },
      { user: users[6], content: "What does the novel suggest about the relationship between language and power?", status: :draft }
    ],
    quiet_upcoming: [
      { user: users[4], content: "ሐዲስ አለማየሁ ስለ ህብረተሰብ ብክነት ምን ማስታወሻ አስቀርቷል?", status: :draft }
    ],
    private_club_session: [
      { user: users[6], content: "Does Harari's 'shared myths' argument hold up against the cultural examples you know?", status: :revealed }
    ]
  }

  question_plan.each do |key, questions|
    bread = reads[key]
    questions.each do |qdata|
      translations = qdata.delete(:translations) || []
      question = DiscussionQuestion.create!(book_read: bread, **qdata)
      translations.each do |t|
        question.question_translations.create!(language_code: t[:language_code], content: t[:content])
      end
    end
  end

  # 9. Membership requests for the private club
  puts "📨 Creating Membership Requests..."
  private_club = created_clubs[5]
  MembershipRequest.create!(book_club: private_club, user: users[7], status: :pending, note: "I have been reading Sapiens and would love to join the discussions!")
  MembershipRequest.create!(book_club: private_club, user: users[2], status: :rejected, note: "Interested in joining the circle.")

  puts "🎉 Seeding complete!"
  puts "📊 Stats: #{User.count} users, #{Book.count} books, #{BookClub.count} clubs, #{BookRead.count} book reads, #{BookReadRsvp.count} RSVPs, #{Poll.count} polls, #{PollVote.count} votes, #{DiscussionQuestion.count} questions, #{MembershipRequest.count} membership requests."
end
