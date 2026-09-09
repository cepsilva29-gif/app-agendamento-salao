# Evolution API — referência rápida

A Evolution API é a camada que fala com o WhatsApp (via protocolo Baileys) e expõe uma API HTTP
simples que o n8n usa para enviar/receber mensagens.

## Enviar uma mensagem de texto

```
POST {EVOLUTION_API_URL}/message/sendText/{EVOLUTION_INSTANCE}
Headers:
  apikey: {EVOLUTION_API_KEY}
  Content-Type: application/json
Body:
{
  "number": "5511999998888",
  "text": "Sua mensagem aqui"
}
```

Usado nos workflows `02-criar-agendamento`, `04-cancelar-agendamento` e
`06-lembrete-automatico` para confirmar, avisar cancelamento e lembrar o cliente.

## Receber mensagens (webhook)

A Evolution API é configurada (via `WEBHOOK_GLOBAL_URL` no `docker-compose.yml`) para enviar
todo evento `messages.upsert` para `https://n8n.engenhariadedadosn8n.shop/webhook/whatsapp-in`, que é o
gatilho do workflow `07-chatbot-whatsapp.json`.

Formato resumido do payload recebido:

```json
{
  "event": "messages.upsert",
  "data": {
    "key": { "remoteJid": "5511999998888@s.whatsapp.net", "fromMe": false },
    "message": { "conversation": "texto da mensagem" }
  }
}
```

O workflow `07-chatbot-whatsapp` ignora mensagens com `fromMe: true` (evita responder a si
mesmo) e interpreta palavras-chave simples (`AGENDAR`, `CANCELAR`, `STATUS`, `AJUDA`) para dar
respostas automáticas — não substitui o app, apenas orienta o cliente a usá-lo.

## Se preferir usar outro provedor de WhatsApp

Os workflows isolam toda chamada de envio de mensagem em nós **HTTP Request** separados —
para trocar por outra API de WhatsApp (ex: WhatsApp Cloud API oficial da Meta), basta editar a
URL/headers/body desses nós pontuais, sem tocar no restante da lógica de agendamento.
