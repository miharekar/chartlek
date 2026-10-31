Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  root to: redirect("/overview")

  resource :overview, only: :show
  get "overview/:year(/:month)", to: "overviews#show", as: :overview_period, constraints: {year: /\d{4}/, month: /0?[1-9]|1[0-2]/}
  resources :runs, only: %i[index show] do
    resource :map, only: :show
  end
  resource :pace_trend, only: :show
  resource :pr_progress, only: :show
  resource :wellness, only: :show
  resource :training_bands, only: :show
  resources :gears, path: "gear", only: :index
  resource :gear_sync, only: :create
  resources :goals
  resource :sync, only: :create
  resource :theme, only: :update
  resource :strava_connection, only: %i[show create]
  get "strava/callback", to: "strava_connections#show", as: :strava_callback
  resource :strava_webhook, only: %i[show create], path: "strava/webhook"
end
