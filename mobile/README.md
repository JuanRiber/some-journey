# Some Journey Mobile

App mobile/web do Some Journey, feito com React Native, Expo, Expo Router e TypeScript.

## O que existe hoje

- Login com JWT
- Cadastro de usuario
- Persistencia segura do token com `expo-secure-store`
- Atlas inicial pos-login com resumo e memoria mais recente
- Timeline agrupada por ano
- Criacao de memoria com titulo, texto, data e localizacao
- Tela de detalhe de memoria
- Picker de localizacao com implementacao web baseada em Leaflet

O mapa principal do atlas ainda e um placeholder honesto. O fluxo de recuperar senha tambem ainda nao envia e-mail real.

## Setup

Instale as dependencias:

```bash
npm install
```

Inicie o app:

```bash
npm run web
```

Outros alvos:

```bash
npm run android
npm run ios
npm start
```

## API

A URL da API e definida em `src/lib/config.ts`.

Padroes:

- Android emulator: `http://10.0.2.2:8000`
- Web, iOS e outros: `http://127.0.0.1:8000`

Para sobrescrever, ajuste `extra.apiUrl` em `app.json`:

```json
{
  "expo": {
    "extra": {
      "apiUrl": "http://127.0.0.1:8000"
    }
  }
}
```

Antes de usar o app, rode o backend na porta `8000`.

## Estrutura

```text
src/
|-- app/          # rotas e telas Expo Router
|-- components/   # UI compartilhada
|-- hooks/
|-- lib/          # api, auth, config, geo
|-- theme/        # cores e estilos
`-- constants/
```

## Scripts

- `npm start`: abre o Expo
- `npm run web`: roda no navegador
- `npm run android`: roda no Android
- `npm run ios`: roda no iOS
- `npm run lint`: executa o lint do Expo
