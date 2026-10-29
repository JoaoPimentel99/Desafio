# Desafio técnico — DevOps

Você herdou a automação de uma frota de servidores de borda com Ubuntu 24.04.
Duas peças foram escritas às pressas:

- um playbook Ansible que instala um agente de heartbeat e endurece o SSH;
- um workflow do GitHub Actions que gera o `.deb` do agente e publica uma
  release quando sai uma tag.

Quem escreveu diz que as duas funcionam. Nenhuma faz o que promete.

## Regras

- **Tempo:** cerca de 2 horas de trabalho. O prazo é de 48 horas depois do
  recebimento.
- **Consulta:** documentação, buscas e assistentes de IA estão liberados.
  Depois há uma conversa de 30 minutos em que você explica cada decisão, então
  use só o que conseguir defender.
- **Escopo:** não precisa reescrever do zero. Corrija o que existe.

## O que entregar

1. As correções num repositório git, **um problema por commit**, com mensagem
   dizendo o que mudou e por quê.
2. Um `NOTAS.md` com, para cada problema: o sintoma, a causa, a correção e
   **como você comprovou** que a correção funciona. Inclua o que achou e
   decidiu não corrigir.
3. As respostas da Parte 3 no mesmo `NOTAS.md`.

Entregue um repositório privado no GitHub com acesso para quem enviou o
desafio, ou um `.zip` da pasta com o diretório `.git`.

## Parte 1 — Ansible (cerca de 70 min)

O playbook (`ansible/site.yml`) deveria, em cada servidor do grupo `edge`:

- instalar `/usr/local/bin/edge-agent` e a unit do systemd, deixar o agente
  ativo e reiniciá-lo quando o binário, a configuração ou a unit mudarem;
- gerar `/etc/edge-agent/edge-agent.conf`. O token da API é segredo;
- desligar o login de root e o login por senha no SSH;
- ser seguro de rodar repetidas vezes numa frota em produção.

### Lab

O lab tem um controlador Ansible e três servidores (`edge1`, `edge2`, `edge3`)
que reproduzem o estado herdado da frota real. Requer Docker com Compose v2
num Linux.

```sh
cd lab
docker compose up -d --build
docker compose exec control ansible-playbook site.yml
docker compose exec control ansible-lint site.yml
docker compose exec edge1 bash      # inspecionar um servidor
docker compose down                 # ao terminar
```

A pasta `ansible/` é montada no controlador, então o que você editar vale na
hora. **Terminar verde não quer dizer que está certo.**

Se um servidor do lab sair logo depois de subir, aumente o limite de inotify
(`sudo sysctl fs.inotify.max_user_instances=512`). Se mesmo assim o lab não
funcionar na sua máquina, avise na hora: o lab não faz parte da avaliação.

## Parte 2 — GitHub Actions (cerca de 40 min)

O workflow (`.github/workflows/release.yml`) deveria:

- em todo push para `main` e em todo pull request: rodar o lint e gerar o
  `.deb`, sem publicar nada;
- numa tag `vX.Y.Z`: gerar o `.deb` com a versão `X.Y.Z` e publicá-lo como
  release do GitHub;
- garantir que um pull request vindo de fork não tenha acesso a segredo nem
  permissão de escrita no repositório.

Para testar, suba esta pasta num repositório privado da sua conta e use tags
de teste. O `pacote/build-deb.sh` roda em qualquer Ubuntu, inclusive em
`docker run --rm -it -v "$PWD:/w" -w /w ubuntu:24.04 bash`.

## Parte 3 — Perguntas (cerca de 10 min)

Responda em 3 a 5 linhas cada.

1. Este playbook vai rodar em 30 servidores de produção que atendem clientes.
   Como você faria o primeiro rollout e como saberia que deu certo?
2. Onde o token da API deveria ficar e como ele chega ao servidor?
3. Uma release saiu com um `.deb` quebrado e já está instalada em 5
   servidores. O que você faz, em ordem?

---

A chave `lab/lab_key` existe só para o lab e não dá acesso a nada fora dele.
