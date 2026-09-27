Rails.application.routes.draw do
  devise_for :users

  root "top#index"

  get "how_to_play", to: "top#how_to_play", as: :how_to_play
  get "game", to: "games#show", as: :game

  resources :catch_records, only: [:create, :index]

  # ヘルスチェック用（Renderのデフォルト運用に合わせる）
  get "up" => "rails/health#show", as: :rails_health_check
end
