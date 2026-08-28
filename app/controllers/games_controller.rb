# ISSUE: ゲーム画面とCanvas+Stimulus基盤の実装
# ゲームのリアルタイム処理はすべてブラウザ側JavaScript（Stimulusコントローラー）が担当し、
# このコントローラーはCanvasを埋め込んだ画面を1枚返すだけの役割にとどめる（README10章の役割分担）。
class GamesController < ApplicationController
  def show
  end
end
