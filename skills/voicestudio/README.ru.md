# Скилл VoiceStudio — как установить

Архив `voicestudio-skill.zip` (~20 КБ) содержит полный скилл. Сам VoiceStudio
(40+ МБ исходников и гигабайты моделей) скилл ставит сам — через официальный
установщик, Docker или из исходников.

## Установка скилла

- **Claude.ai / Claude Desktop:** Настройки → Capabilities → Skills → Upload skill → выберите `voicestudio-skill.zip`.
- **Claude Code:** распакуйте в `~/.claude/skills/` (для всех проектов) или `.claude/skills/` в проекте:
  `unzip voicestudio-skill.zip -d ~/.claude/skills/`

## Использование

Просто скажите Claude: «установи VoiceStudio», «озвучь этот текст моим голосом»,
«склонируй мой голос из файла me.wav», «сделай субтитры к видео», «подключи VoiceStudio по MCP».

Вручную:

```sh
bash scripts/install.sh            # macOS / Linux: приложение
bash scripts/install.sh --docker   # сервер без GUI (добавьте --gpu для NVIDIA)
python3 scripts/vs.py doctor       # проверка готовности
python3 scripts/vs.py speak "Привет!" -o hello.wav --language ru
```

Windows: `powershell -ExecutionPolicy Bypass -File scripts\install.ps1`.
