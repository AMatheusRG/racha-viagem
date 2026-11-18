# 🧳 Racha Viagem

App web para organizar as provisões e dividir os gastos de viagens em grupo (amigos, família, trabalho).

**Acesse:** https://amatheusrg.github.io/racha-viagem/

## O que faz
- **Lista de provisões**: o que levar, quem compra; ao marcar comprado, já lança o gasto.
- **Gastos** com 5 jeitos de dividir: igual, por cota (casal = 2, criança = 0,5), por item (ex.: bebida só para quem bebe), manual e "dividir depois".
- **Resumo visual**: total, gasto por categoria, orçamento, quem recebe e quem deve.
- **Acerto** com o menor número de Pix e **extrato individual pelo WhatsApp** (para quem não usa o app).
- **Convite por link**: qualquer pessoa entra sem cadastro; tudo sincroniza em tempo real.

## Como funciona por dentro
- Página única (`index.html`) hospedada no **GitHub Pages**.
- Banco **Supabase (PostgreSQL)** com regras de acesso por linha (RLS): só quem entrou pelo convite vê a viagem.
- Login anônimo (sem cadastro) e, opcionalmente, acesso salvo por e-mail.
- A chave no código é a **publishable** (pública por natureza). A chave secreta nunca fica aqui.

## Atualizar o app
Substitua o `index.html` neste repositório (Add file → Upload files) e faça commit. Em 1–2 minutos o site atualiza.
