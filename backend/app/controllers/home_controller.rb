class HomeController < ApplicationController
  before_action :start_at_onboarding, only: :index

  def index
  end

  def upcoming
    @upcoming_book_reads = BookRead.includes(:book, :book_club)
      .where("meetup_time >= ?", Time.current)
      .order(meetup_time: :asc, id: :asc)

    set_page_and_extract_portion_from @upcoming_book_reads
    if turbo_frame_request? || request.format.turbo_stream?
      @next_page = @page.next_param
      @has_next_page = !@page.last?
    else
      @next_page = 1
      @has_next_page = true
    end

    respond_to do |format|
      format.html { render partial: "home/upcoming_book_reads" }
      format.turbo_stream
    end
  end

  private

  def start_at_onboarding
    redirect_to onboarding_path if onboarding_pending?
  end
end
