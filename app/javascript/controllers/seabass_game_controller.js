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
    this.caughtFish = false
    this.flying = false
    this.flyFrom = 0
    this.flyTo = 0
    this.flyElapsed = 0
    this.flyDuration = 0
    this.landSplashTimer = 0
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
    // キャストパワーが高いほど遠くまで飛び、リトリーブの開始位置（岸からの距離）が遠くなる。
    // パワーが低いと岸の近くにしか届かず、探れる範囲（＝バイトのチャンス）が短くなる。
    const power = Math.round(this.castPower)
    const targetProgress = Math.max(0, 40 - power * 0.4)

    // ルアーが竿先（岸側）から着水地点まで飛んでいくアニメーション。
    // パワーが強いほど飛距離が長く見え、飛んでいる時間も少し長くなる。
    this.flying = true
    this.flyFrom = 100
    this.flyTo = targetProgress
    this.flyElapsed = 0
    this.flyDuration = 300 + power * 3
    this.lureProgress = this.flyFrom

    this.tapTimestamps = []
    this.stayTimer = 0
    this.biteAccum = 0
    this.msg(`キャスト！ 飛距離パワー ${power}%（遠くまで飛ぶほど探れる範囲が広がる）`)
  }

  updateFlying(dt) {
    this.flyElapsed += dt
    const t = Math.min(1, this.flyElapsed / this.flyDuration)
    const eased = 1 - Math.pow(1 - t, 2) // イーズアウトで着水直前に減速する
    this.lureProgress = this.flyFrom + (this.flyTo - this.flyFrom) * eased
    if (t >= 1) {
      this.flying = false
      this.lureProgress = this.flyTo
      this.landSplashTimer = 260
    }
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
    this.caughtFish = false
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
    if (this.landSplashTimer > 0) this.landSplashTimer -= dt

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

    if (this.state === S.RETRIEVING) {
      if (this.flying) {
        this.updateFlying(dt)
      } else {
        this.updateRetrieving(dt)
      }
    }
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
      this.caughtFish = false
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
        this.caughtFish = false
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
        this.caughtFish = false
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
      this.caughtFish = true
      this.resultText = `キャッチ！ シーバス ${this.fishSize}cm (+${points}pt)`
      this.state = S.RESULT
      this.resultTimer = 2200
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

    if (this.landSplashTimer > 0) {
      // 着水した瞬間の水しぶき。時間経過で輪が広がりながら消える
      const p = 1 - this.landSplashTimer / 260
      ctx.strokeStyle = `rgba(220,240,255,${0.7 * (1 - p)})`
      ctx.lineWidth = 2
      ctx.beginPath()
      ctx.ellipse(lureX, lureY, 8 + p * 26, 4 + p * 10, 0, 0, Math.PI * 2)
      ctx.stroke()
    }

    if (this.state === S.BITE || this.state === S.FIGHT) {
      ctx.fillStyle = "rgba(255,255,255,0.25)"
      ctx.beginPath()
      ctx.ellipse(lureX - 20, lureY + 10, 22, 10, 0, 0, Math.PI * 2)
      ctx.fill()
      this.drawBiteMark(ctx, lureX, lureY)
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

    // 釣れた時はシーバスのイラストとサイズを表示する
    if (this.state === S.RESULT && this.caughtFish) {
      this.drawCatchResult(ctx, canvas)
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

  // バイト中〜ファイト中、ルアーの上に「！」マークを表示する（食いついたことを分かりやすくする）
  drawBiteMark(ctx, x, y) {
    const pulse = (Math.sin(performance.now() / 150) + 1) / 2 // 0〜1で明滅
    const markY = y - 36 - pulse * 4
    const radius = 13 + pulse * 2

    // 吹き出し本体
    ctx.fillStyle = "rgba(255,224,138,0.95)"
    ctx.beginPath()
    ctx.arc(x, markY, radius, 0, Math.PI * 2)
    ctx.fill()
    ctx.strokeStyle = "#c0392b"
    ctx.lineWidth = 2
    ctx.stroke()

    // ルアーを指す吹き出しの三角
    ctx.fillStyle = "rgba(255,224,138,0.95)"
    ctx.beginPath()
    ctx.moveTo(x - 5, markY + radius - 2)
    ctx.lineTo(x, markY + radius + 10)
    ctx.lineTo(x + 5, markY + radius - 2)
    ctx.closePath()
    ctx.fill()

    // ！マーク本体
    ctx.fillStyle = "#c0392b"
    ctx.font = `bold ${Math.round(radius * 1.6)}px sans-serif`
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillText("!", x, markY - 1)
    ctx.textAlign = "left"
    ctx.textBaseline = "alphabetic"
  }

  // 釣れた瞬間のリザルト演出（シーバスのイラスト＋サイズ表示）
  drawCatchResult(ctx, canvas) {
    const cx = canvas.width / 2
    const cy = canvas.height / 2 - 10

    ctx.fillStyle = "rgba(13,27,36,0.6)"
    ctx.fillRect(0, 0, canvas.width, canvas.height)

    this.drawSeabass(ctx, cx, cy - 10, this.fishSize)

    ctx.textAlign = "center"
    ctx.fillStyle = "#ffe08a"
    ctx.font = "bold 22px sans-serif"
    ctx.fillText("キャッチ！", cx, cy - 70)

    ctx.font = "bold 18px sans-serif"
    ctx.fillStyle = "#eaf2f5"
    ctx.fillText(`シーバス ${this.fishSize} cm`, cx, cy + 62)
    ctx.textAlign = "left"
  }

  // シーバス（スズキ）を模した簡易イラスト。sizeCmが大きいほど体を大きく描く
  drawSeabass(ctx, cx, cy, sizeCm) {
    const scale = 0.85 + Math.min(70, Math.max(25, sizeCm)) / 100
    const bodyLength = 100 * scale
    const bodyHeight = 30 * scale

    ctx.save()
    ctx.translate(cx, cy)

    // 尾びれ
    ctx.fillStyle = "#8fb6c4"
    ctx.beginPath()
    ctx.moveTo(-bodyLength / 2, 0)
    ctx.lineTo(-bodyLength / 2 - 20 * scale, -16 * scale)
    ctx.lineTo(-bodyLength / 2 - 20 * scale, 16 * scale)
    ctx.closePath()
    ctx.fill()

    // 胸びれ
    ctx.fillStyle = "#7ea3b1"
    ctx.beginPath()
    ctx.moveTo(bodyLength / 6, bodyHeight / 4)
    ctx.lineTo(bodyLength / 6 - 6 * scale, bodyHeight / 2 + 14 * scale)
    ctx.lineTo(bodyLength / 6 + 10 * scale, bodyHeight / 4)
    ctx.closePath()
    ctx.fill()

    // 体
    const grad = ctx.createLinearGradient(0, -bodyHeight / 2, 0, bodyHeight / 2)
    grad.addColorStop(0, "#d5e3e8")
    grad.addColorStop(1, "#6f95a3")
    ctx.fillStyle = grad
    ctx.beginPath()
    ctx.ellipse(0, 0, bodyLength / 2, bodyHeight / 2, 0, 0, Math.PI * 2)
    ctx.fill()

    // 背びれ
    ctx.fillStyle = "#5c7d8a"
    ctx.beginPath()
    ctx.moveTo(-12 * scale, -bodyHeight / 2)
    ctx.lineTo(14 * scale, -bodyHeight / 2)
    ctx.lineTo(0, -bodyHeight / 2 - 18 * scale)
    ctx.closePath()
    ctx.fill()

    // 側線
    ctx.strokeStyle = "rgba(20,30,40,0.35)"
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(-bodyLength / 2 + 12, 0)
    ctx.lineTo(bodyLength / 2 - 16, 0)
    ctx.stroke()

    // 口
    ctx.strokeStyle = "rgba(20,30,40,0.5)"
    ctx.beginPath()
    ctx.moveTo(bodyLength / 2 - 4 * scale, 4 * scale)
    ctx.lineTo(bodyLength / 2 + 6 * scale, 6 * scale)
    ctx.stroke()

    // 目
    ctx.fillStyle = "#16232c"
    ctx.beginPath()
    ctx.arc(bodyLength / 2 - 18 * scale, -4 * scale, 3.2 * scale, 0, Math.PI * 2)
    ctx.fill()

    ctx.restore()
  }
}
