Rails.application.routes.draw do
  namespace :admin do
    resources :books do
      member { post :enrich }
    end
    resources :book_clubs
    resources :book_club_members
    resources :book_reads
    resources :polls
    resources :poll_options
    resources :poll_votes
    resources :book_tags
    resources :discussion_questions
    resources :ratings
    resources :reviews
    resources :review_likes
    resources :tags
    resources :users

    root to: "books#index"
  end
  devise_for :users, controllers: {
    registrations: "users/registrations",
    sessions: "users/sessions"
  }
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", :as => :rails_health_check

  # Social logins
  get "/telegram_mini_app/login", to: "telegram_mini_app_login#create", as: :telegram_mini_app_login
  get "/telegram_login/callback", to: "telegram_login#callback", as: :telegram_login_callback
  get "/line_login/authorize", to: "line_login#authorize", as: :line_login_authorize
  get "/line_login/callback", to: "line_login#callback", as: :line_login_callback
  get "upcoming_book_reads", to: "home#upcoming", as: :upcoming_book_reads

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#index"

  get "/books/search", to: "books#search", as: :books_search

  # Book resources (public)
  resources :books do
    resources :ratings, only: [ :create ]
    resources :reviews, only: [ :create ] do
      resource :like, only: [ :create ], controller: "review_likes"
    end
    member do
      get :cover
    end
  end

  resources :book_clubs do
    collection do
      get :discover
    end

    resource :membership, controller: "book_club_members", only: [ :create, :destroy ]
    resources :members, controller: "book_club_members", only: [ :update, :destroy ]
    resources :membership_requests, only: [ :create ] do
      member do
        patch :approve
        patch :reject
        delete :cancel
      end
    end
    resources :book_reads do
      resource :rsvp, controller: "book_read_rsvps", only: [ :create, :update ]
      resources :discussion_questions, only: [ :create, :update, :destroy ]
      resources :poll_votes, only: [ :create ]

      member do
        get :finalize
        patch :select_book
      end
    end
  end

  get "library", to: "books#index", as: :library

  # Simple API namespace for small JSON endpoints
  namespace :api do
    namespace :v1 do
      # GET /api/v1/auth/check - returns JSON about current authentication state
      get "auth/check", to: "auth#check"
    end
  end

  # Secure dashboard to only admin users
  authenticate :user, ->(u) { u.admin? } do
    mount MissionControl::Jobs::Engine, at: "/jobs"
    mount Stoplight::Admin, at: "/stoplights"
  end

  authenticate :user do
    resources :users, only: [ :index, :show ]
    get "profile", to: "users#show", as: :profile
  end

  resources :configurations, only: [] do
    get :ios_v1, on: :collection
    get :android_v1, on: :collection
  end

  get "privacy", to: "pages#privacy", as: :privacy
  get "terms", to: "pages#terms", as: :terms

  # Deep linking & app association endpoints
  get ".well-known/apple-app-site-association", to: "well_known#apple_app_site_association"
  get "apple-app-site-association", to: "well_known#apple_app_site_association"
  get ".well-known/assetlinks.json", to: "well_known#assetlinks", format: false
end
