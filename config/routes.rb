Rails.application.routes.draw do
  root "top#index"

  get "how_to_play", to: "top#how_to_play", as: :how_to_play
  get "game", to: "games#show", as: :game

  # ヘルスチェック用（Renderのデフォルト運用に合わせる）
  get "up" => "rails/health#show", as: :rails_health_check
end
