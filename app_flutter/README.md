# Some Journey — app Flutter

O único cliente do Some Journey: o mesmo código para celular e web.

- **Versões:** Dart `^3.10.9`; o CI usa Flutter `3.38.10`.
- **Onde estão as coisas:** `lib/api.dart` é o único lugar que fala com a API;
  `lib/screens/` tem as telas; `lib/features/*/` guarda a lógica de cada assunto
  (o que é regra fica em Dart puro, sem Flutter, e é testado); `lib/design/` é o
  design system — tokens, tema e componentes.
- **Rodar:**

  ```bash
  flutter pub get
  flutter run --dart-define=API_URL=http://127.0.0.1:8000
  ```

- **Antes de enviar:** `flutter analyze --fatal-infos` e `flutter test`. O
  repositório **não** é formatado com `dart format` — não rode.
- **Build web:** `flutter build web --no-web-resources-cdn` (o motivo do flag
  está no README da raiz). Os cabeçalhos de segurança do site ficam em
  `web/_headers`.

Setup completo, entrar com Google, deploy e convenções: no
[README da raiz](../README.md) e em [`docs/`](../docs/).
