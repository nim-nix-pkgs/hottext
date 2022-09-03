# SPDX-License-Identifier: Unlicense

import pixie, hashes, tables, typography, typography/svgfont, unicode, vmath
import streams, strutils
import sdl2

from os import getEnv, splitfile

const
  fontPathEnvKey = "HOTTEXT_FONT_PATH"
  fontSizeEnvKey = "HOTTEXT_FONT_SIZE"
  wpmKey = "HOTTEXT_WPM"

proc defaultFont(): tuple[data: string, ext: string] =
  let path = getEnv(fontPathEnvKey)
  if path != "":
    result.ext = path.splitFile.ext.toLower
    case result.ext
    of ".otf", ".svg", ".ttf": discard
    else: raiseAssert("invalid compile-time font: " & path)
    result.data = readFile(path)

const (defaultFontData, defaultFontExt) = defaultFont()

type
  GlyphKey = object
    rune: Rune
    size: float
    subPixelShift: int
  GlyphEntry = object
    image: Image
    texture: TexturePtr
    glyphOffset: Vec2
  GlyphCache = Table[GlyphKey, GlyphEntry]

proc hash(key: GlyphKey): Hash =
  hashData(unsafeAddr key, sizeof key)

#[
proc `=destroy`(glyph: var GlyphEntry) =
  destroy(glyph.texture)
]#

type State = object
  font: Font
  glyphCache: GlyphCache
  words: seq[string]
  window: WindowPtr
  renderer: RendererPtr
  wpm, period, delay, pos: int
  paused: bool

proc `=destroy`(state: var State) =
  destroy(state.renderer)
  destroy(state.window)

func isEmpty(state: State): bool = state.words.len == 0

proc feedText(state: var State; text: string) =
  for word in unicode.splitWhitespace(text):
    if word != "": state.words.add(word)

proc fillWords(state: var State) =
  var line: string
  while stdin.readLine(line):
    state.feedText(line)
  if state.isEmpty: state.words.add("…")

proc newTexture(state: var State; image: Image): TexturePtr =
  const
    rmask = uint32 0x000000ff
    gmask = uint32 0x0000ff00
    bmask = uint32 0x00ff0000
    amask = uint32 0xff000000
  var surface = createRGBSurfaceFrom(
    addr image.data[0],
    cint image.width,
    cint image.height,
    32,
    cint image.width shl 2,
    rmask, gmask, bmask, amask)
  result = state.renderer.createTextureFromSurface(surface)
  freeSurface(surface)

proc `[]`(state: var State; pos: GlyphPosition): GlyphEntry =
  let
    font = pos.font
    key = GlyphKey(rune: pos.rune, size: font.size, subPixelShift: int(pos.subPixelShift * 10))
  result = state.glyphCache.getOrDefault(key)
  if result.texture.isNil:
    assert(pos.character in font.typeface.glyphs)
    var glyph = font.typeface.glyphs[pos.character]
    result.image = font.getGlyphImage(
        glyph, result.glyphOffset,
        subPixelShift = quantize(pos.subPixelShift, 0.1))
    result.texture = newTexture(state, result.image)
    state.glyphCache[key] = result

proc render(state: var State) =
  assert(state.pos < state.words.len)
  state.delay = state.period
  if state.pos < 5:
    state.delay.inc(state.period div 2)
  elif state.pos < 3:
    state.delay.inc(state.period)
  let
    word = state.words[state.pos]
    wordLen = word.runeLen
  assert(wordLen != 0)
  if wordLen < 2:
    state.delay.inc(state.period div 3)
  elif wordLen > 9:
    state.delay.inc(state.period div 2)
  var width, height: cint
  state.window.getSize(width, height)
  let
    hCenter = width div 2
    fixationOffset = (int) (wordLen.float / 9) * 3
  state.renderer.clear()
  #[
  when not defined(release):
    let vCenter = height div 2
    discard state.renderer.setDrawColor(0'u8, 0'u8, 0xff'u8)
    state.renderer.drawLine(hCenter, vCenter - 20, hCenter, vCenter + 20)
    state.renderer.drawLine(hCenter - 20, vCenter, hCenter + 20, vCenter)
  discard state.renderer.setDrawColor(0xff'u8, 0xff'u8, 0xff'u8)
  ]#
  block wpmCounter:
    let normalSize = state.font.size
    state.font.size = state.font.size / 2
    let layout = state.font.typeset(
        $state.wpm & " WPM ",
        vec2(width.float, height.float),
        hAlign=Right, vAlign=Bottom)
    for i, pos in layout:
      let glyph = state[pos]
      var destRect = sdl2.rect(
          cint pos.rect.x + glyph.glyphOffset.x,
          cint pos.rect.y + glyph.glyphOffset.y,
          cint glyph.image.width,
          cint glyph.image.height)
      discard glyph.texture.setTextureColorMod(0x80, 0x80, 0x80)
      state.renderer.copy(glyph.texture, nil, addr destRect)
    state.font.size = normalSize
  block:
    let
      layout = state.font.typeset(
          word,
          vec2(width.float / 2, height.float / 2),
          hAlign=Center, vAlign=Top)
      fixationPos = layout[fixationOffset]
      fixationShift = hCenter.float - fixationPos.rect.x - (fixationPos.rect.w / 2)
    for i, pos in layout:
      if not pos.rune.isAlpha:
        if i == layout.high and pos.character == ".":
          state.delay.inc(state.period * 2)
        else:
          state.delay.inc(state.period div 4)
      let glyph = state[pos]
      var destRect = sdl2.rect(
          cint pos.rect.x + glyph.glyphOffset.x + fixationShift,
          cint pos.rect.y + glyph.glyphOffset.y,
          cint glyph.image.width,
          cint glyph.image.height)
      if i == fixationOffset:
        discard glyph.texture.setTextureColorMod(0xff, 0, 0)
      else:
        discard glyph.texture.setTextureColorMod(0, 0, 0)
      state.renderer.copy(glyph.texture, nil, addr destRect)

proc initState(): State =
  let fontPath = getEnv(fontPathEnvKey)
  if fontPath != "":
    case fontPath.splitFile.ext.toLower
    of ".otf":
      result.font = readFontOtf(fontPath)
    of ".svg":
      result.font = readFontSvg(fontPath)
    of ".ttf":
      result.font = readFontTtf(fontPath)
  else:
    if defaultFontData == "":
      echo "No font set with ", fontPathEnvKey
      quit(-1)
    case defaultFontExt
    of ".otf":
      result.font = defaultFontData.parseOtf
    of ".svg":
      result.font = defaultFontData.newStringStream.readFontSvg
    of ".ttf":
      result.font = defaultFontData.parseTtf
    else: discard
  let fontSizeStr = getEnv(fontSizeEnvKey)
  result.font.size =
      if fontSizeStr == "": 48
      else: fontSizeStr.parseInt
  result.glyphCache = initTable[GlyphKey, GlyphEntry]()
  result.words = newSeq[string]()
  discard createWindowAndRenderer(
      640, 480,
      SDL_WINDOW_SHOWN or SDL_WINDOW_RESIZABLE,
      result.window, result.renderer)
  let wpmStr = getEnv(wpmKey)
  result.wpm =
      if wpmStr == "": 400
      else: wpmStr.parseInt
  result.period = 60_000 div result.wpm

proc present(state: var State) = state.renderer.present()

proc togglePause(state: var State) =
  state.paused = not state.paused
  if state.paused:
    enableScreenSaver()
    state.renderer.clear()
    discard state.renderer.setDrawColor(0xc0'u8, 0xc0'u8, 0xc0'u8)
  else:
    disableScreenSaver()
    state.renderer.clear()
    discard state.renderer.setDrawColor(0xff'u8, 0xff'u8, 0xff'u8)
  state.render()
  state.present()

proc pasteText(state: var State) =
  if hasClipboardText():
    state.pos = 0
    state.words.setLen(0)
    state.words.add(" ")
    let paste = getClipboardText()
    state.feedText($paste)
    freeClipboardText(paste)
    if state.paused:
      state.togglePause()

proc adjustRate(state: var State; change: cint) =
  let
    delta = 10 * change
    wpm = state.wpm + delta
  if wpm > 0:
    state.wpm = wpm
    state.period = 60_000 div state.wpm
    state.render()
    state.present()

discard sdl2.init(INIT_VIDEO or INIT_EVENTS)
block mainLoop:
  var
    state = initState()
    event: Event
    delay: cint
  state.fillWords()
  state.togglePause()
  while true:
    if not waitEventTimeout(event, delay):
      if not state.paused:
        state.present()
        if state.pos < state.words.high:
          inc(state.pos)
          delay = state.delay.cint
          state.render()
        else:
          state.togglePause()
    else:
      case event.kind
      of MouseMotion: discard
      of MouseButtonUp:
        case event.button.button
        of BUTTON_LEFT:
          state.togglePause()
        of BUTTON_MIDDLE:
          state.pasteText()
        else: discard
      of MouseWheel:
        state.adjustRate(event.wheel.y)
      of WindowEvent:
        if not state.paused and event.window.event in {WindowEvent_Hidden, WindowEvent_FocusLost}:
          state.togglePause()
        else:
          state.render()
      of KeyUp:
        try:
          let code = event.key.keysym.sym.Scancode
          if code in {SDL_SCANCODE_SPACE, SDL_SCANCODE_PAUSE}:
            state.togglePause()
          elif code in {SDL_SCANCODE_PASTE}:
            state.pasteText()
          elif code in {SDL_SCANCODE_Q, SDL_SCANCODE_ESCAPE}:
            break mainLoop
        except:
           # invalid event.key.keysym.sym sometimes arrive
          discard
      of TextInput:
        for c in event.text.text:
          case c
          of char(0): break
          of ' ': state.togglePause()
          of 'q': break mainLoop
          else: discard
      of QuitEvent:
        break mainLoop
      else: discard

sdl2.quit()
