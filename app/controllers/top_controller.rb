# ISSUE: TOPページ（タイトル画面）の作成
# ISSUE: 操作説明（チュートリアル）画面
class TopController < ApplicationController
  def index
    # タイトル画面。「あそぶ」「操作説明を見る」の導線のみを持つ静的ページ。
  end

  def how_to_play
    # 操作説明（チュートリアル）画面。操作を1回説明する導線。
  end
end
