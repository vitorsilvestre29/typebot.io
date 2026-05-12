# Typebot para o Fluxozap na Railway

Este repo deve subir como infraestrutura interna do Fluxozap. Nao suba como um unico servico.

## Servicos

Crie 4 servicos no mesmo projeto da Railway:

1. `typebot-postgres`
   - Plugin Postgres da Railway.

2. `typebot-redis`
   - Plugin Redis da Railway.

3. `typebot-builder`
   - Deploy pelo GitHub usando `Dockerfile.builder`.
   - Gere um dominio publico para este servico.
   - Use a porta que aparecer nos logs do container. Normalmente a Railway injeta `PORT=8080`.

4. `typebot-viewer`
   - Deploy pelo GitHub usando `Dockerfile.viewer`.
   - Gere um dominio publico para este servico.
   - Use a porta que aparecer nos logs do container. Normalmente a Railway injeta `PORT=8080`.

## Variaveis obrigatorias nos dois servicos

Use os mesmos valores em `typebot-builder` e `typebot-viewer`:

```env
DATABASE_URL=${{typebot-postgres.DATABASE_URL}}
REDIS_URL=${{typebot-redis.REDIS_URL}}
ENCRYPTION_SECRET=gere-uma-string-com-32-caracteres
NEXTAUTH_URL=https://url-do-typebot-builder.up.railway.app
NEXT_PUBLIC_VIEWER_URL=https://url-do-typebot-viewer.up.railway.app
NODE_OPTIONS=--no-node-snapshot
```

No `typebot-builder`, adicione tambem:

```env
ADMIN_EMAIL=seu-email-admin
DISABLE_SIGNUP=true
```

## Depois do deploy

1. Acesse o builder.
2. Crie/entre com o admin.
3. Crie um workspace.
4. Crie uma API key no Typebot.
5. Copie:
   - Builder URL
   - Viewer URL
   - API key
   - Workspace ID

## Configurar no Fluxozap

No Fluxozap, em `Integracoes > Construtor de fluxos`, use:

```env
URL do motor de fluxos = https://url-do-typebot-builder.up.railway.app
Chave interna = API key criada no Typebot
Workspace ID = workspace id do Typebot
URL da API interna = https://url-do-typebot-builder.up.railway.app/api/v1
URL publica dos bots = https://url-do-typebot-viewer.up.railway.app
Template interno = /_fluxo-builder/typebots/{{typebotId}}
```

Depois disso:

1. Volte em `Fluxos`.
2. Clique em `Preparar construtor`.
3. Abra o construtor dentro do Fluxozap.
4. Publique o fluxo.
5. Em `Vinculos`, clique em `Publicar no WhatsApp`.

## O que foi removido do deploy

O `.dockerignore` ignora pastas de agentes, IDE, docs, landing page e arquivos de changelog/contribuicao. O codigo fonte continua no repo, mas nao entra no contexto de build da imagem.
