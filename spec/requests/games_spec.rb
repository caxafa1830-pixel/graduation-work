require "rails_helper"

RSpec.describe "Games", type: :request do
  describe "GET /game" do
    it "ゲーム画面が表示される" do
      get game_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="seabass-game"')
    end
  end
end
