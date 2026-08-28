require "rails_helper"

RSpec.describe "Top", type: :request do
  describe "GET /" do
    it "タイトル画面が表示される" do
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("シーバスカップ")
    end
  end

  describe "GET /how_to_play" do
    it "操作説明画面が表示される" do
      get how_to_play_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("操作説明")
    end
  end
end
