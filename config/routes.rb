Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#index"

  get 'pipeline', to: 'pipeline#index', as: :pipeline
  post 'pipeline/retry/:id', to: 'pipeline#retry', as: :pipeline_retry
  get 'pipeline/seed', to: 'pipeline#seed_status', as: :pipeline_seed_status
  post 'pipeline/seed', to: 'pipeline#seed', as: :pipeline_seed

  get 'reviews', to: 'reviews#index', as: :reviews
  post 'reviews/approve', to: 'reviews#approve', as: :reviews_approve
  post 'reviews/push_to_gmail/:id', to: 'reviews#push_to_gmail', as: :reviews_push_to_gmail

  get 'bulk_import', to: 'bulk_imports#new', as: :new_bulk_import
  post 'bulk_import', to: 'bulk_imports#create', as: :bulk_imports

  resources :prospects, only: %i[index create] do
    member do
      post :research_now
    end
  end
end
