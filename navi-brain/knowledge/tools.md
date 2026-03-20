# NAVI — VERKTYGSREFERENS

## Tillgängliga verktyg

### read_file(path, start_line?, end_line?)
Läs filinnehåll med radnummer. Använd alltid innan du editerar.
- Stora filer: använd start_line/end_line för att läsa specifika sektioner
- Exempel: read_file("src/index.ts", 50, 100)

### write_file(path, content)
Skriv komplett fil. Skapar föräldrakataloger automatiskt. Kör lint efteråt.
- Använd för nya filer eller fullständiga omskrivningar
- Läs alltid originalet först om filen finns

### edit_file(path, old_text, new_text)
Exakt sök/ersätt. old_text MÅSTE matcha verbatim — läs filen först.
- Misslyckas om old_text inte finns exakt i filen
- Föredra denna över write_file för punktredigeringar

### run_command(command, cwd?, timeout?)
Kör shell-kommando. Säker för långa operationer. Standard timeout: 120s.
- Standardkatalog: sessionens workspace
- Timeout max: 600s
- Exempel: run_command("npm install && npm test")
- Exempel: run_command("swift build 2>&1 | tail -20")

### grep(pattern, path, file_pattern?, context_lines?)
Sök filinnehåll med regex. Returnerar matchande rader med kontext.
- Exempel: grep("func sendPush", "navi-brain/")
- Exempel: grep("import Foundation", "EonCode/", "*.swift")

### list_files(path, recursive?)
Lista filer. Exkluderar node_modules, .git, .build.
- Föredra glob() för specifika filtyper

### glob(pattern, base_path?)
Hitta filer med glob-mönster. Snabbare än list_files för specifika typer.
- Exempel: glob("**/*.swift", "/root/workspace/MyProject")
- Exempel: glob("**/*.ts", "/root/workspace/api/src")

### web_search(query)
Sök webben. Använd för: felmeddelanden, biblioteksdokumentation, Stack Overflow.
- Exempel: web_search("swiftui wkwebview intrinsic content size")
- Exempel: web_search("node-apn send notification example")

### fetch_url(url)
Hämta URL-innehåll. Använd för: GitHub raw-filer, officiell dokumentation, API:er.
- Exempel: fetch_url("https://raw.githubusercontent.com/user/repo/main/README.md")
- Trunkeras vid 8000 tecken

### todo_write(todos)
Uppdatera TODO-listan. Anropa vid start + när planen ändras. Synlig för användaren i realtid.
- Varje todo: { id, title, done }
- Ersätter hela listan — inkludera alla todos

### git_commit(message, cwd?)
Stagea alla ändringar och committa. Returnerar commit-hash.
- Använd vid varje viktig milstolpe
- Format: "feat(scope): beskrivning" eller "fix(scope): beskrivning"

### create_directory(path)
Skapa katalog och alla föräldrakataloger.

---

## Verktygsvalsguid

| Behov | Verktyg |
|-------|---------|
| Läs del av stor fil | read_file med start_line/end_line |
| Hitta var funktion definieras | grep("func funktionsnamn", path) |
| Hitta alla Swift-filer | glob("**/*.swift", workDir) |
| Installera paket | run_command("npm install paket") |
| Kolla om kod kompilerar | run_command("swift build 2>&1") |
| Slå upp API-dokumentation | fetch_url(officiell docs URL) |
| Felsök felmeddelande | web_search("exakt felmeddelande") |
| Redigera specifik rad | read_file → edit_file |
| Skapa ny fil | write_file |

---

## Kritiska regler

1. **Läs alltid filen INNAN du editerar** — edit_file kräver exakt textmatch
2. **Kör alltid bygget** — påstå aldrig framgång utan gröna tester/bygge
3. **Committa vid milstolpar** — inte allt på slutet
4. **Sök innan du antar** — använd grep/glob för att förstå kodbasen
5. **web_search vid fel** — sök på exakta felmeddelanden, sök inte på allmänt
