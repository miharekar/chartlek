Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root to: redirect("/overview")

  resource :overview, only: :show
  get "overview/:year(/:month)", to: "overviews#show", as: :overview_period, constraints: {year: /\d{4}/, month: /0?[1-9]|1[0-2]/}
  resource :pace_trend, only: :show
  resource :sync, only: :create
end
