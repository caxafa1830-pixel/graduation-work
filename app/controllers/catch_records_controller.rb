# 捕獲記録の保存・一覧表示を担当するコントローラー。
# ゲームロジック自体はブラウザ側JavaScriptが担当し、ここでは記録の永続化のみを行う。
class CatchRecordsController < ApplicationController
  before_action :authenticate_user!

  def index
    @catch_records = current_user.catch_records.order(score: :desc)
  end

  def create
    record = current_user.catch_records.new(catch_record_params)
    if record.save
      render json: { ok: true, best: current_user.catch_records.maximum(:score) || 0 }
    else
      render json: { ok: false, errors: record.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def catch_record_params
    params.require(:catch_record).permit(:fish_size_cm, :score)
  end
end
