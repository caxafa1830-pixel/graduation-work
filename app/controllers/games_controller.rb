# ISSUE: ゲーム画面とCanvas+Stimulus基盤の実装
# ゲームのリアルタイム処理はすべてブラウザ側JavaScript（Stimulusコントローラー）が担当し、
# このコントローラーはCanvasを埋め込んだ画面を1枚返すだけの役割にとどめる（README10章の役割分担）。
class GamesController < ApplicationController
  before_action :authenticate_user!

  def show
    @best_score = current_user.catch_records.maximum(:score) || 0
  end
end
