class BookClubsController < ApplicationController
  before_action :authenticate_user!, except: [ :index, :show, :discover ]
  before_action :set_book_club, only: [ :show, :edit, :update ]
  before_action -> { authorize_club_owner!(@club) }, only: [ :edit, :update ]

  def index
    if turbo_frame_request?
      set_book_clubs
      is_my_clubs_filter_active = params["filter"] != "all" && current_user.present?
      if is_my_clubs_filter_active
        @clubs = @clubs.where(id: @joined_club_ids).or(BookClub.where(owner_id: current_user.id))
      end
      set_page_and_extract_portion_from @clubs

      @next_page = @page.next_param
      @has_next_page = !@page.last?
    else
      @next_page = 1
      @has_next_page = true
    end

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def show
    now = Time.current
    @upcoming_reads = @club.book_reads.includes(:book).where("meetup_time >= ?", now).order(meetup_time: :asc)
    @current_read = @upcoming_reads.first
    @past_reads = @club.book_reads
      .includes(:book, :host, :discussion_questions, book_read_rsvps: :user)
      .where("meetup_time < ?", now)
      .order(meetup_time: :desc)
  end

  # Kicks off the Literature DNA flow (deterministic collector + sandboxed AI
  # analysis) in the background and returns immediately.
  def generate_dna
    club = BookClub.find(params[:id])
    return head :forbidden unless club_manageable_by?(club)

    if ENV["OTARI_API_KEY"].blank?
      return redirect_to book_club_path(club),
        alert: "Otari is not configured — set OTARI_BASE_URL and OTARI_API_KEY."
    end

    begin
      BookClubDnaJob.perform_later(club.id)
    rescue StandardError => e
      return redirect_to book_club_path(club), alert: "DNA generation failed: #{e.message}"
    end
    redirect_to book_club_path(club),
      notice: "Literature DNA queued for “#{club.name}” — it runs in the background (usually under a minute). Refresh to see the tab."
  end

  def new
    @club = BookClub.new
  end

  def create
    @club = current_user.owned_book_clubs.build(club_params)
    if @club.save
      redirect_to book_club_path(@club), notice: "Book Club created successfully."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @club.update(club_params)
      redirect_to book_club_path(@club), notice: "Book Club updated successfully."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def edit
  end

  def discover
    set_book_clubs
    @clubs = @clubs.limit(50)

    render partial: "home/book_clubs_carousel"
  end

  private

  # Mirrors ApplicationController#authorize_club_owner!'s condition, without
  # the redirect (this action answers the Turbo/button request directly).
  def club_manageable_by?(club)
    club.owner == current_user || club.book_club_members.exists?(user: current_user, role: :admin)
  end

  def set_book_clubs
    # TODO: Filter by city or have search by city, by name, topic mechanism
    @joined_club_ids = current_user ? BookClubMember.where(user_id: current_user.id).pluck(:book_club_id) : []
    @clubs = BookClub.by_relevance
  end

  def club_params
    params.require(:book_club).permit(:name, :description, :is_private, :application_form_url, :cover_photo, :photo)
  end

  def set_book_club
    @club = BookClub.find(params[:id])
  end
end
