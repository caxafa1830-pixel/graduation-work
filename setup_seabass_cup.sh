#!/usr/bin/env bash
# シーバスカップ MVP セットアップスクリプト
#
# 使い方:
#   1. 既存の Rails リポジトリ（~/graduation-work など）のルートに、このファイルを置く
#   2. bash setup_seabass_cup.sh
#   3. bundle install → bin/rails server で確認
#
# 既存ファイルは上書きされるので注意してください。
set -e

echo "==> ディレクトリを作成しています..."
mkdir -p app/controllers
mkdir -p app/views/layouts
mkdir -p app/views/top
mkdir -p app/views/games
mkdir -p app/assets/stylesheets
mkdir -p app/javascript/controllers
mkdir -p config/initializers
mkdir -p spec/requests
mkdir -p spec/factories
mkdir -p .github/workflows

echo "==> ルート直下のファイルを作成しています..."

cat > Gemfile << 'EOF'
source "https://rubygems.org"

ruby "3.2.2"

gem "rails", "~> 7.1"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"
gem "bootsnap", require: false
gem "enum_help"

group :development, :test do
  gem "debug", platforms: %i[mri windows]
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-rspec", require: false
end

group :development do
  gem "web-console"
  gem "bullet"
end

group :test do
  gem "simplecov", require: false
end
EOF

cat > .rubocop.yml << 'EOF'
require:
  - rubocop-rails
  - rubocop-rspec

AllCops:
  NewCops: enable
  TargetRubyVersion: 3.2
  Exclude:
    - "bin/**/*"
    - "db/**/*"
    - "config/**/*"
    - "vendor/**/*"

Style/Documentation:
  Enabled: false

Metrics/BlockLength:
  Exclude:
    - "spec/**/*"
EOF

cat > .gitignore << 'EOF'
/log/*
/tmp/*
/storage/*
/coverage/
!/log/.keep
!/tmp/.keep
/public/assets
.byebug_history
/config/master.key
/.env*
!/.env.example
/node_modules
EOF

cat > render.yaml << 'EOF'
# ISSUE: 初回デプロイ（Render）
# Render の Blueprint (render.yaml) を使ったデプロイ設定。
# 実際のデプロイはRenderダッシュボード側でこのファイルを読み込んで行う。
services:
  - type: web
    name: seabass-cup
    env: ruby
    plan: free
    buildCommand: "bundle install && bin/rails assets:precompile"
    startCommand: "bin/rails server -p $PORT -e production"
    envVars:
      - key: RAILS_MASTER_KEY
        sync: false
      - key: DATABASE_URL
        fromDatabase:
          name: seabass-cup-db
          property: connectionString

databases:
  - name: seabass-cup-db
    plan: free
EOF

cat > SETUP_NOTES.md << 'EOF'
# セットアップ手順（このコードをローカルで動かす場合）

このコードは、Claudeの作業環境（サンドボックス）にRuby on Rails・PostgreSQLをインストールできなかったため
（rubygems.orgへのネットワークアクセス不可、sudo不可）、実行・自動テストの実施ができていません。
手書きでファイル一式を作成した状態です。ばくさんの手元のRails環境（`~/graduation-work`）で
以下の手順で動作確認をしてください。

1. このディレクトリの中身を、既存のRailsリポジトリの対応する場所にコピーする
   （すでに `rails new` 済みのリポジトリがあれば、Gemfileの差分だけ反映してもよい）
2. `bundle install`
3. `bin/rails db:create db:migrate`（MVPではテーブルは使わないが、Rails起動のために実行）
4. `bin/rails server` で起動し、`http://localhost:3000` を開く
5. `bundle exec rspec` でテストを実行
6. `bundle exec rubocop` でLintを実行

## 動作確認のポイント

- タイトル画面 → 操作説明 → ゲーム画面の遷移が導線通りか
- Enterキーの「押しっぱなし（キャスト）」「連打（リトリーブ）」「押す/離す（ファイト）」が
  それぞれ狙い通りに区別されているか（README 7章・10章で懸念していた点）
- Spaceキーのトゥイッチが、Enterキーの連打と混同されずに動くか
- タイムアップ後、自己ベスト（localStorageのseabassCup.bestScore）が更新され、
  ブラウザを再読み込みしても保持されているか

## 未実装・要調整の可能性がある点

- キャスト成功後の飛距離（castPower）は現状パワーゲージの表示のみで、
  リトリーブの距離計算には直接反映していません（README通り、まずはコアループの手触りを優先した簡易実装）
- バイト確率やテンションの閾値は仮の数値です。プレイして「間延びしないか」「テンションがシビアすぎないか」を
  実際に確認しながら調整してください
- CIワークフロー（.github/workflows/ci.yml）はPostgreSQLコンテナを前提にしていますが、
  MVPは実際にはDBを使わないため、`db:schema:load`が空のスキーマでも通ることを一度確認してください
EOF

echo "==> config/ のファイルを作成しています..."

cat > config/routes.rb << 'EOF'
Rails.application.routes.draw do
  root "top#index"

  get "how_to_play", to: "top#how_to_play", as: :how_to_play
  get "game", to: "games#show", as: :game

  # ヘルスチェック用（Renderのデフォルト運用に合わせる）
  get "up" => "rails/health#show", as: :rails_health_check
end
EOF

cat > config/database.yml << 'EOF'
# MVPの段階ではDBを使用する機能はないが、README10章の技術スタック方針（Rails + PostgreSQL）
# に合わせて構成だけ用意しておく。本リリースでusers/lures/user_lures/fields/catchesを追加する。
default: &default
  adapter: postgresql
  encoding: unicode
  host: <%= ENV.fetch("DATABASE_HOST", "localhost") %>
  username: <%= ENV.fetch("DATABASE_USERNAME", "postgres") %>
  password: <%= ENV.fetch("DATABASE_PASSWORD", "") %>
  pool: <%= ENV.fetch("RAILS_MAX_THREADS", 5) %>

development:
  <<: *default
  database: seabass_cup_development

test:
  <<: *default
  database: seabass_cup_test

production:
  <<: *default
  database: seabass_cup_production
  url: <%= ENV["DATABASE_URL"] %>
EOF

cat > config/importmap.rb << 'EOF'
pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
EOF

cat > config/initializers/bullet.rb << 'EOF'
if Rails.env.development?
  Rails.application.config.after_initialize do
    Bullet.enable = true
    Bullet.alert = true
    Bullet.bullet_logger = true
    Bullet.console = true
    Bullet.rails_logger = true
  end
end
EOF

echo "==> app/controllers/ のファイルを作成しています..."

cat > app/controllers/application_controller.rb << 'EOF'
class ApplicationController < ActionController::Base
end
EOF

cat > app/controllers/top_controller.rb << 'EOF'
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
EOF

cat > app/controllers/games_controller.rb << 'EOF'
# ISSUE: ゲーム画面とCanvas+Stimulus基盤の実装
# ゲームのリアルタイム処理はすべてブラウザ側JavaScript（Stimulusコントローラー）が担当し、
# このコントローラーはCanvasを埋め込んだ画面を1枚返すだけの役割にとどめる（README10章の役割分担）。
class GamesController < ApplicationController
  def show
  end
end
EOF

echo "==> app/views/ のファイルを作成しています..."

cat > app/views/layouts/application.html.erb << 'EOF'
<!DOCTYPE html>
<html>
  <head>
    <title>シーバスカップ</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>

    <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>

  <body>
    <%= yield %>
  </body>
</html>
EOF

cat > app/views/top/index.html.erb << 'EOF'
<div class="title-screen">
  <h1>シーバスカップ</h1>
  <p class="title-screen__copy">
    天候や時間の都合で釣りに行けないルアー釣り経験者のための、<br>
    ブラウザで遊べるアクション型ルアー釣りゲーム
  </p>

  <div class="title-screen__buttons">
    <%= link_to "あそぶ", game_path, class: "btn btn--primary" %>
    <%= link_to "操作説明を見る", how_to_play_path, class: "btn btn--secondary" %>
  </div>
</div>
EOF

cat > app/views/top/how_to_play.html.erb << 'EOF'
<div class="how-to-play">
  <h1>操作説明</h1>

  <ul class="how-to-play__list">
    <li><strong>キャスト</strong>：Enterキーを押しっぱなしでパワーを溜め、離すとキャストします。</li>
    <li><strong>リトリーブ（巻く）</strong>：Enterキーを連打する速さがリール速度になります。</li>
    <li><strong>トゥイッチ</strong>：Spaceキーを1回押すとルアーが跳ねます。</li>
    <li><strong>フッキング</strong>：バイトの合図が出たらすぐにEnterキーを押します。</li>
    <li><strong>ファイト</strong>：Enterキーを押して巻き、離してテンションを緩めます。</li>
  </ul>

  <div class="how-to-play__buttons">
    <%= link_to "はじめる", game_path, class: "btn btn--primary" %>
    <%= link_to "戻る", root_path, class: "btn btn--secondary" %>
  </div>
</div>
EOF

cat > app/views/games/show.html.erb << 'EOF'
<div data-controller="seabass-game" class="game-screen">
  <canvas data-seabass-game-target="canvas" width="640" height="360"></canvas>

  <div class="game-screen__panel">
    <div>状態: <span data-seabass-game-target="state">READY</span></div>
    <div>残り時間: <span data-seabass-game-target="timer">180</span> 秒</div>
    <div>
      スコア: <span data-seabass-game-target="score">0</span>
      匹数: <span data-seabass-game-target="catches">0</span>
      自己ベスト: <span data-seabass-game-target="best">0</span>
    </div>

    <div class="bar-bg"><div data-seabass-game-target="castBar" class="bar-fill bar-fill--cast"></div></div>
    <div class="bar-bg"><div data-seabass-game-target="progressBar" class="bar-fill bar-fill--progress"></div></div>
    <div class="bar-bg"><div data-seabass-game-target="tensionBar" class="bar-fill bar-fill--tension"></div></div>
    <div class="bar-bg"><div data-seabass-game-target="staminaBar" class="bar-fill bar-fill--stamina"></div></div>

    <div data-seabass-game-target="message" class="game-screen__message"></div>

    <%= link_to "タイトルへ戻る", root_path, class: "btn btn--secondary" %>
  </div>
</div>
EOF

echo "==> app/assets/ のファイルを作成しています..."

cat > app/assets/stylesheets/application.css << 'EOF'
/*
 *= require_tree .
 *= require_self
 */

body {
  background: #16232c;
  color: #eaf2f5;
  font-family: "Hiragino Sans", "Yu Gothic", sans-serif;
  margin: 0;
}

.title-screen, .how-to-play {
  max-width: 640px;
  margin: 60px auto;
  text-align: center;
  padding: 0 20px;
}

.btn {
  display: inline-block;
  padding: 10px 24px;
  margin: 8px;
  border-radius: 6px;
  text-decoration: none;
  font-weight: bold;
}

.btn--primary {
  background: #7fd8ff;
  color: #0d1b24;
}

.btn--secondary {
  background: transparent;
  color: #7fd8ff;
  border: 1px solid #7fd8ff;
}

.how-to-play__list {
  text-align: left;
  line-height: 1.8;
}

.game-screen {
  display: flex;
  gap: 20px;
  max-width: 980px;
  margin: 20px auto;
  padding: 0 20px;
}

.game-screen canvas {
  background: #0d1b24;
  border: 2px solid #3a5a6d;
  border-radius: 6px;
}

.game-screen__panel {
  width: 260px;
}

.bar-bg {
  width: 100%;
  height: 12px;
  background: #0d1b24;
  border: 1px solid #3a5a6d;
  border-radius: 6px;
  overflow: hidden;
  margin-bottom: 6px;
}

.bar-fill {
  height: 100%;
  width: 0%;
}

.bar-fill--cast { background: #7fd8ff; }
.bar-fill--progress { background: #7fffb0; }
.bar-fill--tension { background: #ffb37f; }
.bar-fill--stamina { background: #ff7f7f; }

.game-screen__message {
  min-height: 40px;
  color: #ffe08a;
  font-weight: bold;
  margin: 10px 0;
}
EOF

echo "==> app/javascript/ のファイルを作成しています..."

cat > app/javascript/application.js << 'EOF'
import "@hotwired/turbo-rails"
import "controllers"
EOF

cat > app/javascript/controllers/application.js << 'EOF'
import { Application } from "@hotwired/stimulus"

const application = Application.start()
application.debug = false
window.Stimulus = application

export { application }
EOF

cat > app/javascript/controllers/index.js << 'EOF'
import { application } from "controllers/application"

import SeabassGameController from "controllers/seabass_game_controller"
application.register("seabass-game", SeabassGameController)
EOF

cat > app/javascript/controllers/seabass_game_controller.js << 'JSEOF'
import { Controller } from "@hotwired/stimulus"

// ISSUE: コアループ(キャスト〜ファイト)の実装
// ISSUE: リザルト・カップ終了画面・自己ベスト保存の実装
//
// README 10章の役割分担どおり、ゲームのリアルタイム処理(毎フレームのループ・入力判定・描画)は
// すべてこのStimulusコントローラー(ブラウザ側JavaScript)が担当する。Rails/DBはMVPでは使用しない。
export default class extends Controller {
  static targets = [
    "canvas", "state", "timer", "score", "catches", "best",
    "message", "castBar", "progressBar", "tensionBar", "staminaBar"
  ]

  static STATE = {
    READY: "READY",
    CASTING: "CASTING",
    RETRIEVING: "RETRIEVING",
    BITE: "BITE",
    FIGHT: "FIGHT",
    RESULT: "RESULT",
    GAMEOVER: "GAMEOVER"
  }

  static BEST_SCORE_KEY = "seabassCup.bestScore"
  static BEST_SIZE_KEY = "seabassCup.bestSize"
  static HOOK_WINDOW_MS = 450
  static GAME_SECONDS = 180

  connect() {
    this.ctx = this.canvasTarget.getContext("2d")
    this.resetAll()

    this.onKeydown = this.handleKeydown.bind(this)
    this.onKeyup = this.handleKeyup.bind(this)
    this.onRestartKey = this.handleRestartKey.bind(this)
    window.addEventListener("keydown", this.onKeydown)
    window.addEventListener("keyup", this.onKeyup)
    window.addEventListener("keydown", this.onRestartKey)

    this.lastTs = performance.now()
    this.loopBound = this.loop.bind(this)
    this.rafId = requestAnimationFrame(this.loopBound)
  }

  disconnect() {
    window.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("keyup", this.onKeyup)
    window.removeEventListener("keydown", this.onRestartKey)
    if (this.rafId) cancelAnimationFrame(this.rafId)
  }

  // ---- 状態初期化 ----
  resetAll() {
    const S = this.constructor.STATE
    this.state = S.READY
    this.timeLeft = this.constructor.GAME_SECONDS
    this.score = 0
    this.catches = 0
    this.best = Number(localStorage.getItem(this.constructor.BEST_SCORE_KEY) || 0)
    this.bestSize = Number(localStorage.getItem(this.constructor.BEST_SIZE_KEY) || 0)

    this.gameTimeAccum = 0
    this.resetForNextCast()
  }

  resetForNextCast() {
    const S = this.constructor.STATE
    this.state = this.state === S.GAMEOVER ? S.GAMEOVER : S.READY
    this.enterDown = false
    this.enterDownAt = 0
    this.castPower = 0
    this.lureProgress = 0
    this.tapTimestamps = []
    this.lastTapAt = 0
    this.stayTimer = 0
    this.twitchFlashTimer = 0
    this.biteAccum = 0
    this.hookWindowTimer = 0
    this.tension = 40
    this.stamina = 100
    this.tensionHighTimer = 0
    this.tensionLowTimer = 0
    this.resultTimer = 0
    this.resultText = ""
    this.fishSize = 0
  }

  // ---- 入力 ----
  handleKeydown(e) {
    const S = this.constructor.STATE
    if (this.state === S.GAMEOVER) return

    if (e.code === "Enter" || e.code === "NumpadEnter") {
      if (!this.enterDown) {
        this.enterDown = true
        this.enterDownAt = performance.now()
      }
      if (!e.repeat) this.handleEnterTap()
      e.preventDefault()
    }

    if (e.code === "Space") {
      if (!e.repeat && this.state === S.RETRIEVING) this.doTwitch()
      e.preventDefault()
    }
  }

  handleKeyup(e) {
    const S = this.constructor.STATE
    if (e.code === "Enter" || e.code === "NumpadEnter") {
      if (this.state === S.CASTING) this.doCast()
      this.enterDown = false
    }
  }

  handleRestartKey(e) {
    const S = this.constructor.STATE
    if (e.code === "KeyR" && this.state === S.GAMEOVER) {
      this.resetAll()
    }
  }

  handleEnterTap() {
    const S = this.constructor.STATE
    const now = performance.now()

    if (this.state === S.READY) {
      this.state = S.CASTING
    } else if (this.state === S.RETRIEVING) {
      this.tapTimestamps.push(now)
      this.tapTimestamps = this.tapTimestamps.filter((t) => now - t <= 1000)
      this.lastTapAt = now
      this.stayTimer = 0
    } else if (this.state === S.BITE) {
      this.tryHook()
    }
    // FIGHT状態はenterDownの押しっぱなし判定(handleKeydown/up)のみで処理する
  }

  doCast() {
    const S = this.constructor.STATE
    this.state = S.RETRIEVING
    this.lureProgress = 0
    this.tapTimestamps = []
    this.stayTimer = 0
    this.biteAccum = 0
    this.msg(`キャスト！ 飛距離パワー ${Math.round(this.castPower)}%`)
  }

  doTwitch() {
    this.twitchFlashTimer = 150
    this.biteAccum += 8
    this.msg("トゥイッチ！")
  }

  tryHook() {
    const S = this.constructor.STATE
    if (this.state !== S.BITE) return
    this.state = S.FIGHT
    this.tension = 40
    this.stamina = 100 - Math.min(40, this.fishSize)
    this.tensionHighTimer = 0
    this.tensionLowTimer = 0
    this.msg("フッキング成功！ファイト開始")
  }

  missHook() {
    const S = this.constructor.STATE
    this.msg("アワセが遅れてバラシ...")
    this.resultText = "バラシ（フッキング失敗）"
    this.state = S.RESULT
    this.resultTimer = 1500
  }

  startBite() {
    const S = this.constructor.STATE
    this.state = S.BITE
    this.hookWindowTimer = this.constructor.HOOK_WINDOW_MS
    this.msg("バイト！ すぐにEnterでアワセろ！")
  }

  msg(text) {
    if (this.hasMessageTarget) this.messageTarget.textContent = text
  }

  // ---- ゲームループ ----
  loop(ts) {
    const dt = ts - this.lastTs
    this.lastTs = ts
    this.update(dt)
    this.render()
    this.rafId = requestAnimationFrame(this.loopBound)
  }

  update(dt) {
    const S = this.constructor.STATE
    if (this.state === S.GAMEOVER) return

    if (this.twitchFlashTimer > 0) this.twitchFlashTimer -= dt

    if (this.state !== S.RESULT) {
      this.gameTimeAccum += dt
      if (this.gameTimeAccum >= 1000) {
        this.gameTimeAccum -= 1000
        this.timeLeft -= 1
        if (this.timeLeft <= 0) {
          this.timeLeft = 0
          this.finishCup()
        }
      }
    }

    if (this.state === S.CASTING && this.enterDown) {
      const held = performance.now() - this.enterDownAt
      this.castPower = Math.min(100, held / 12)
    }

    if (this.state === S.RETRIEVING) this.updateRetrieving(dt)
    if (this.state === S.BITE) this.updateBite(dt)
    if (this.state === S.FIGHT) this.updateFight(dt)
    if (this.state === S.RESULT) this.updateResult(dt)

    this.updateHud()
  }

  updateRetrieving(dt) {
    const S = this.constructor.STATE
    const now = performance.now()
    this.tapTimestamps = this.tapTimestamps.filter((t) => now - t <= 1000)
    const rate = this.tapTimestamps.length

    this.stayTimer = now - this.lastTapAt > 800 ? this.stayTimer + dt : 0

    const speed = Math.min(rate, 6) * 0.9
    this.lureProgress = Math.min(100, this.lureProgress + speed * (dt / 200))

    let actionScore = 0
    if (rate >= 2 && rate <= 4) actionScore = 1.2
    else if (rate > 0) actionScore = 0.5
    if (this.stayTimer > 400 && this.stayTimer < 1500) actionScore += 0.8
    this.biteAccum += actionScore * (dt / 200)

    const biteChance = Math.min(0.02, this.biteAccum / 4000)
    if (Math.random() < biteChance * (dt / 16)) this.startBite()

    if (this.lureProgress >= 100) {
      this.msg("ルアーが岸に戻ってきた（ノーバイト）")
      this.resultText = "ノーバイト"
      this.state = S.RESULT
      this.resultTimer = 1200
    }
  }

  updateBite(dt) {
    this.hookWindowTimer -= dt
    if (this.hookWindowTimer <= 0) this.missHook()
  }

  updateFight(dt) {
    const S = this.constructor.STATE
    this.tension = this.enterDown
      ? Math.min(100, this.tension + dt * 0.08)
      : Math.max(0, this.tension - dt * 0.06)

    const inSafeZone = this.tension >= 30 && this.tension <= 70
    if (inSafeZone && this.enterDown) {
      this.stamina = Math.max(0, this.stamina - dt * 0.03)
    }

    if (this.tension > 90) {
      this.tensionHighTimer += dt
      if (this.tensionHighTimer > 500) {
        this.resultText = "ラインブレイクでバラシ！"
        this.state = S.RESULT
        this.resultTimer = 1500
      }
    } else {
      this.tensionHighTimer = 0
    }

    if (this.tension < 8) {
      this.tensionLowTimer += dt
      if (this.tensionLowTimer > 900) {
        this.resultText = "テンション抜けでバラシ！"
        this.state = S.RESULT
        this.resultTimer = 1500
      }
    } else {
      this.tensionLowTimer = 0
    }

    if (this.stamina <= 0 && this.state === S.FIGHT) {
      this.fishSize = 25 + Math.round(Math.random() * 45)
      const points = this.fishSize * 10
      this.score += points
      this.catches += 1
      if (this.fishSize > this.bestSize) this.bestSize = this.fishSize
      this.resultText = `キャッチ！ シーバス ${this.fishSize}cm (+${points}pt)`
      this.state = S.RESULT
      this.resultTimer = 1800
    }
  }

  updateResult(dt) {
    const S = this.constructor.STATE
    this.resultTimer -= dt
    this.msg(this.resultText)
    if (this.resultTimer <= 0) this.resetForNextCast()
  }

  finishCup() {
    const S = this.constructor.STATE
    this.state = S.GAMEOVER

    // ISSUE: 自己ベスト（localStorage）機能
    if (this.score > this.best) {
      this.best = this.score
      localStorage.setItem(this.constructor.BEST_SCORE_KEY, String(this.best))
    }
    if (this.bestSize > 0) {
      localStorage.setItem(this.constructor.BEST_SIZE_KEY, String(this.bestSize))
    }
  }

  updateHud() {
    if (this.hasStateTarget) this.stateTarget.textContent = this.state
    if (this.hasTimerTarget) this.timerTarget.textContent = this.timeLeft
    if (this.hasScoreTarget) this.scoreTarget.textContent = this.score
    if (this.hasCatchesTarget) this.catchesTarget.textContent = this.catches
    if (this.hasBestTarget) this.bestTarget.textContent = this.best
    if (this.hasCastBarTarget) this.castBarTarget.style.width = `${this.castPower}%`
    if (this.hasProgressBarTarget) this.progressBarTarget.style.width = `${this.lureProgress}%`
    if (this.hasTensionBarTarget) this.tensionBarTarget.style.width = `${this.tension}%`
    if (this.hasStaminaBarTarget) this.staminaBarTarget.style.width = `${this.stamina}%`
  }

  // ---- 描画 ----
  render() {
    const ctx = this.ctx
    const canvas = this.canvasTarget
    ctx.clearRect(0, 0, canvas.width, canvas.height)

    const lureX = 60 + (canvas.width - 140) * (this.lureProgress / 100)
    const lureY = 250

    this.drawSky(ctx, canvas)
    this.drawWater(ctx, canvas)
    this.drawShore(ctx, canvas)
    this.drawAngler(ctx, canvas, lureX, lureY)

    const S = this.constructor.STATE

    if (this.twitchFlashTimer > 0) {
      ctx.strokeStyle = "rgba(127,216,255,0.8)"
      ctx.beginPath()
      ctx.arc(lureX, lureY, 20 - this.twitchFlashTimer / 10, 0, Math.PI * 2)
      ctx.stroke()
    }

    if (this.state === S.BITE || this.state === S.FIGHT) {
      ctx.fillStyle = "rgba(255,255,255,0.25)"
      ctx.beginPath()
      ctx.ellipse(lureX - 20, lureY + 10, 22, 10, 0, 0, Math.PI * 2)
      ctx.fill()
    }

    ctx.fillStyle = this.state === S.BITE ? "#ffe08a" : "#7fd8ff"
    ctx.beginPath()
    ctx.arc(lureX, lureY, 8, 0, Math.PI * 2)
    ctx.fill()

    ctx.font = "13px sans-serif"
    if (this.state === S.CASTING || this.state === S.READY) {
      ctx.fillStyle = "#eaf2f5"
      ctx.fillText("Enterを押しっぱなしでキャスト、離すと投げる", 20, 30)
    }
    if (this.state === S.RETRIEVING) {
      ctx.fillStyle = "#eaf2f5"
      ctx.fillText("Enter連打=巻く速さ / 止める=ステイ / Space=トゥイッチ", 20, 30)
    }
    if (this.state === S.BITE) {
      ctx.fillStyle = "#ffe08a"
      ctx.font = "bold 16px sans-serif"
      ctx.fillText("Enterでアワセろ！", 20, 30)
    }
    if (this.state === S.FIGHT) {
      ctx.fillStyle = "#eaf2f5"
      ctx.fillText("Enterを押して巻く/離してテンションを緩める", 20, 30)
    }

    if (this.state === S.GAMEOVER) {
      ctx.fillStyle = "rgba(0,0,0,0.7)"
      ctx.fillRect(0, 0, canvas.width, canvas.height)
      ctx.fillStyle = "#ffe08a"
      ctx.font = "bold 22px sans-serif"
      ctx.textAlign = "center"
      ctx.fillText("タイムアップ！", canvas.width / 2, 140)
      ctx.font = "16px sans-serif"
      ctx.fillText(
        `匹数: ${this.catches}　スコア: ${this.score}　自己ベスト: ${this.best}`,
        canvas.width / 2,
        175
      )
      ctx.fillText("R キーでリスタート", canvas.width / 2, 205)
      ctx.textAlign = "left"
    }
  }

  ellipseShape(ctx, x, y, w, h) {
    ctx.beginPath()
    ctx.ellipse(x, y, w, h, 0, 0, Math.PI * 2)
    ctx.fill()
  }

  drawSky(ctx, canvas) {
    const grad = ctx.createLinearGradient(0, 0, 0, 140)
    grad.addColorStop(0, "#16233a")
    grad.addColorStop(1, "#c9793f")
    ctx.fillStyle = grad
    ctx.fillRect(0, 0, canvas.width, 140)

    ctx.fillStyle = "rgba(255,235,190,0.9)"
    this.ellipseShape(ctx, 110, 55, 16, 16)

    ctx.fillStyle = "rgba(20,30,45,0.45)"
    this.ellipseShape(ctx, 300, 40, 40, 10)
    this.ellipseShape(ctx, 335, 48, 26, 8)
    this.ellipseShape(ctx, 470, 32, 50, 11)

    ctx.fillStyle = "#12202c"
    const buildings = [
      { x: 0, w: 28, h: 40 }, { x: 32, w: 20, h: 60 }, { x: 56, w: 26, h: 34 },
      { x: 150, w: 18, h: 22 }, { x: 400, w: 22, h: 28 },
      { x: 520, w: 30, h: 50 }, { x: 555, w: 22, h: 30 }, { x: 585, w: 35, h: 45 }
    ]
    buildings.forEach((b) => ctx.fillRect(b.x, 140 - b.h, b.w, b.h))
  }

  drawWater(ctx, canvas) {
    const grad = ctx.createLinearGradient(0, 140, 0, canvas.height)
    grad.addColorStop(0, "#2a4a5c")
    grad.addColorStop(1, "#0d1b24")
    ctx.fillStyle = grad
    ctx.fillRect(0, 140, canvas.width, canvas.height - 140)

    ctx.strokeStyle = "rgba(255,255,255,0.08)"
    ctx.lineWidth = 1
    const t = performance.now() / 600
    for (let i = 0; i < 5; i++) {
      ctx.beginPath()
      const y = 160 + i * 35
      for (let x = 0; x <= canvas.width; x += 10) {
        const wy = y + Math.sin(x * 0.03 + t + i) * 3
        if (x === 0) ctx.moveTo(x, wy)
        else ctx.lineTo(x, wy)
      }
      ctx.stroke()
    }
  }

  drawShore(ctx, canvas) {
    ctx.fillStyle = "#2b4a2f"
    ctx.fillRect(canvas.width - 40, 140, 40, canvas.height - 140)

    ctx.strokeStyle = "#3f6b45"
    ctx.lineWidth = 2
    for (let i = 0; i < 6; i++) {
      const rx = canvas.width - 36 + i * 3
      ctx.beginPath()
      ctx.moveTo(rx, 150 + i * 2)
      ctx.quadraticCurveTo(rx - 4, 130, rx - 2, 108)
      ctx.stroke()
    }
  }

  drawAngler(ctx, canvas, lureX, lureY) {
    const S = this.constructor.STATE
    const ax = canvas.width - 22
    const ay = 132

    ctx.strokeStyle = "#e8d9c0"
    ctx.lineWidth = 3
    ctx.lineCap = "round"

    ctx.beginPath()
    ctx.arc(ax, ay - 20, 6, 0, Math.PI * 2)
    ctx.stroke()

    ctx.beginPath()
    ctx.moveTo(ax, ay - 14)
    ctx.lineTo(ax, ay + 8)
    ctx.stroke()

    ctx.beginPath()
    ctx.moveTo(ax, ay + 8)
    ctx.lineTo(ax - 6, ay + 20)
    ctx.moveTo(ax, ay + 8)
    ctx.lineTo(ax + 6, ay + 20)
    ctx.stroke()

    const rodBaseX = ax - 5
    const rodBaseY = ay - 6
    ctx.beginPath()
    ctx.moveTo(ax, ay - 8)
    ctx.lineTo(rodBaseX, rodBaseY)
    ctx.stroke()

    const bend = this.state === S.FIGHT ? Math.sin(performance.now() / 80) * 4 : 0
    const rodTipX = rodBaseX - 55
    const rodTipY = rodBaseY - 32 + bend
    ctx.strokeStyle = "#5a3d2b"
    ctx.lineWidth = 2
    ctx.beginPath()
    ctx.moveTo(rodBaseX, rodBaseY)
    ctx.quadraticCurveTo(rodBaseX - 25, rodBaseY - 28, rodTipX, rodTipY)
    ctx.stroke()

    ctx.strokeStyle = "rgba(255,255,255,0.5)"
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(rodTipX, rodTipY)
    if (this.state === S.READY || this.state === S.CASTING) {
      ctx.lineTo(rodTipX + 4, rodTipY + 18)
    } else {
      ctx.lineTo(lureX, lureY)
    }
    ctx.stroke()
    ctx.lineCap = "butt"
  }
}
JSEOF

echo "==> spec/ のファイルを作成しています..."

cat > spec/spec_helper.rb << 'EOF'
# ISSUE: カバレッジ測定ツール（SimpleCov）の導入
require "simplecov"
SimpleCov.start "rails" do
  add_filter "/spec/"
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
end
EOF

cat > spec/rails_helper.rb << 'EOF'
require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_path = Rails.root.join("spec/fixtures")
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include FactoryBot::Syntax::Methods
end
EOF

touch spec/factories/.keep

cat > spec/requests/top_spec.rb << 'EOF'
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
EOF

cat > spec/requests/games_spec.rb << 'EOF'
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
EOF

echo "==> .github/workflows/ のファイルを作成しています..."

cat > .github/workflows/ci.yml << 'EOF'
name: CI

on:
  pull_request:
  push:
    branches: [main]

jobs:
  rubocop:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - name: Run RuboCop
        run: bundle exec rubocop

  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        ports: ["5432:5432"]
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    env:
      RAILS_ENV: test
      DATABASE_HOST: localhost
      DATABASE_USERNAME: postgres
      DATABASE_PASSWORD: postgres
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - name: Set up database
        run: |
          bin/rails db:create
          bin/rails db:schema:load
      - name: Run tests
        run: bundle exec rspec
      - name: Upload coverage
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage
EOF

echo "==> 完了しました！ 作成されたファイル一覧:"
find . -type f \( \
  -name "Gemfile" -o \
  -name ".rubocop.yml" -o \
  -name ".gitignore" -o \
  -name "render.yaml" -o \
  -name "SETUP_NOTES.md" -o \
  -path "./config/*" -o \
  -path "./app/*" -o \
  -path "./spec/*" -o \
  -path "./.github/*" \
  \) -newer Gemfile -o -name "Gemfile" | sort
