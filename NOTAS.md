# NOTAS — desafio DevOps

**Status:** correções feitas nos arquivos. **Ainda não comitadas e não executadas.** Nesta máquina não há git, Docker, ansible-lint nem shellcheck, então a comprovação de cada item abaixo é a prevista (o comando que vai provar), não um resultado.

## Parte 1 — Ansible

### A1. Token da API no repositório e impresso no log
- **Sintoma:** `group_vars/edge.yml` tem o token `tk_live_…` em texto puro. A task "Confere o token" o imprime no log.
- **Causa:** segredo tratado como configuração comum.
- **Correção:** o valor saiu do repositório. A variável lê `EDGE_AGENT_TOKEN` do ambiente do controlador. Uma `assert` falha se ela estiver vazia. A task que gera o `.conf` tem `no_log: true`. A task de debug foi removida.
- **Comprovação prevista:** sem `EDGE_AGENT_TOKEN` o playbook para na `assert`. Com ela, `grep` na saída do Ansible não encontra o token.
- **Ação fora do código:** o token já está no histórico do git. Apagar o arquivo não o invalida. **Rotacione o token na API central.**

### A2. Arquivo de configuração com permissão errada
- **Sintoma:** `mode: 644` no template do `.conf`, que contém o token.
- **Causa:** sem aspas, o YAML lê `644` como número decimal, não como permissão octal. Além disso, 0644 deixa o token legível por todos.
- **Correção:** `mode: "0600"`, dono e grupo `root`.
- **Comprovação prevista:** `stat -c '%a %U:%G' /etc/edge-agent/edge-agent.conf` → `600 root:root`.

### A3. Binário copiado com `shell: cp`
- **Sintoma:** a task aparece sempre como `changed`, e trocar o agente não reinicia o serviço.
- **Causa:** `shell` com `cp` não compara conteúdo e não tem `notify`.
- **Correção:** `ansible.builtin.copy` com modo `0755` e `notify`.
- **Comprovação prevista:** segunda execução com `changed=0`. Alterar o script e rodar de novo dispara o handler.

### A4. Config alterada não reinicia o agente
- **Causa:** a task do template não tinha `notify`.
- **Correção:** `notify` no template, no binário e na unit.

### A5. Unit nova não é recarregada pelo systemd
- **Sintoma:** mudar `edge-agent.service` não tem efeito até `daemon-reload` manual. Na primeira execução, o `start` pode falhar.
- **Correção:** `daemon_reload: true` na task que sobe o serviço e no handler.

### A6. Falha do agente escondida
- **Sintoma:** `ignore_errors: true` na task que sobe o serviço. O playbook termina verde com o agente parado.
- **Correção:** removido.

### A7. Hardening do SSH nunca executa
- **Sintoma:** `PermitRootLogin` e `PasswordAuthentication` continuam como estavam.
- **Causa, em dois pontos:**
  1. `when: ansible_distribution == "ubuntu"`. O fato do Ansible é `"Ubuntu"`, com maiúscula. A condição é falsa e a role não faz nada.
  2. Mesmo que rodasse, o `lineinfile` sem `regexp` só acrescenta linhas. No Ubuntu, `sshd_config.d/` é lido antes do arquivo principal, e o primeiro valor vence. O drop-in `50-cloud-init.conf` (com `PasswordAuthentication yes`) ganharia.
- **Correção:** drop-in `00-edge-hardening.conf`, que é lido antes do `50-`. Condição com `"Ubuntu"`. Validação `sshd -t` antes do restart.
- **Comprovação prevista:** `sshd -T | grep -E 'permitrootlogin|passwordauthentication'` → `no` nos dois.
- **Risco:** antes de rodar em produção, confirme que o login por chave do usuário `deploy` funciona e mantenha uma sessão aberta.

### A8. Script do agente pode apagar o sistema de arquivos
- **Sintoma:** `rm -rf $STATE_DIR/*` sem aspas e sem checagem. Se `STATE_DIR` estiver vazio no `.conf`, o comando vira `rm -rf /*` como root.
- **Correção:** `rm -rf -- "${STATE_DIR:?}"/*`. Se a variável estiver vazia, o script aborta. A correção está nas duas cópias do script (`ansible/roles/edge_agent/files/` e `pacote/`).
- **Comprovação prevista:** `STATE_DIR= bash edge-agent.sh` aborta com erro. `shellcheck` não acusa mais SC2086 nessa linha.

## Parte 2 — GitHub Actions

### W1. Fork com acesso a segredo e token de escrita
- **Sintoma:** `pull_request_target` com `checkout` do SHA do PR. Código de fork roda com `DEB_SIGNING_KEY` e com token de escrita.
- **Causa:** `pull_request_target` roda no contexto do repositório base. Com o head do PR, executa código não confiável com privilégio.
- **Correção:** trocado por `pull_request`, sem `checkout` do head (o padrão já é o merge commit). `permissions: contents: read` global, e `contents: write` só no job de release. O secret `DEB_SIGNING_KEY` foi removido porque nenhum passo o usava.
- **Comprovação prevista:** um PR de fork de teste não recebe secrets e não consegue escrever no repositório.

### W2. Release nunca roda
- **Causa:** `startsWith(github.ref, 'refs/heads/v')`. Tags são `refs/tags/`, então a condição nunca é verdadeira.
- **Correção:** `if: github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')`.

### W3. Release sem o `.deb`
- **Causa:** o job `release` roda em outro runner e não baixa o artefato.
- **Correção:** `needs: build` e `actions/download-artifact`.

### W4. Versão errada no pacote
- **Sintoma:** `VERSION=refs/tags/v1.2.3`. O nome e a versão do `.deb` ficam inválidos.
- **Causa:** `github.ref` em vez de `github.ref_name`, sem remover o `v`. A expressão `${{ }}` era colada dentro do `run:`, o que permite injeção de shell.
- **Correção:** step que usa `ref_type`. Tag `vX.Y.Z` vira `X.Y.Z`. Branch ou PR vira `0.0.0+git<sha>`. O valor passa por `env`. `build-deb.sh` rejeita versão fora do formato dpkg.
- **Comprovação prevista:** `./pacote/build-deb.sh 1.2.3` gera `dist/edge-agent_1.2.3_all.deb`, e `dpkg-deb -I` mostra `Version: 1.2.3`. `build-deb.sh 'a/b'` aborta.

### W5. Lint que não reprova
- **Causa:** `continue-on-error: true` no lint.
- **Correção:** removido. Agora um erro do shellcheck falha o job.

### W6. Actions em branch, não em versão
- **Causa:** `actions/checkout@main` e `upload-artifact@main`. Uma mudança upstream altera o pipeline sem aviso, e o job tem token de escrita.
- **Correção:** `@v4`. **Recomendado:** fixar o SHA do commit.

## Decidi não corrigir (ou corrigir só parcialmente)
- **`ansible.cfg`: `host_key_checking = False`.** Deixa o SSH vulnerável a man-in-the-middle. Mantido porque o lab não tem `known_hosts`. Em produção, a chave do host deve ser provisionada antes do rollout.
- **`ansible.cfg`: `private_key_file = /lab/lab_key`.** Caminho do lab, não deveria estar num repositório de produção. Mantido para o lab rodar.
- **Duas cópias de `edge-agent.sh`.** Corrigi as duas, mas o risco de divergência continua. A solução é uma fonte só.
- **Caminhos divergentes.** O playbook instala `/usr/local/bin/edge-agent` (como pede o README). A unit do pacote usa `/usr/bin/edge-agent`. Numa máquina com o `.deb` e a role, há duas cópias. Convergir para o pacote como única fonte é o próximo passo.
- **`Depends: bash` no `control`.** `logger` e `date` vêm de pacotes essenciais do Ubuntu. Mantido.

## Parte 3 — Perguntas

1. **Rollout em 30 servidores.** Começaria por um servidor (`serial: 1` ou um lote de 2 a 3), com `--check --diff` antes. Depois, lotes maiores com `max_fail_percentage: 0`, para parar no primeiro erro. Saberia que deu certo por três checagens: `systemctl is-active edge-agent`, heartbeat recente em `/var/lib/edge-agent/heartbeat` (mais novo que 2 × intervalo), e uma segunda execução com `changed=0`. Com o SSH, mantenho uma sessão aberta e testo um login novo antes de fechar a anterior.

2. **Onde fica o token.** Fora do repositório: Ansible Vault ou um gerenciador de segredos, lido pelo controlador. Chega ao servidor por SSH, gravado em `/etc/edge-agent/edge-agent.conf` com modo `0600`, `root:root`, e sem aparecer no log (`no_log`). Não passo o token em linha de comando (aparece em `ps`). O ideal é um token por servidor, com escopo mínimo, que se possa rotacionar.

3. **Release quebrado já instalado em 5 servidores, em ordem:**
   1. Conter: pausar o rollout e a promoção da release, sem instalar em mais servidores.
   2. Avaliar: `systemctl status edge-agent` e `dpkg -l edge-agent` nos 5, para medir o impacto.
   3. Reverter: reinstalar a versão anterior boa (`apt-get install edge-agent=<versão>`). Por isso o repositório de pacotes deve manter as versões antigas.
   4. Comunicar, e marcar ou remover a release quebrada. Não reutilizar a tag: publicar uma versão nova.
   5. Corrigir para frente e fechar com postmortem, perguntando que teste teria pego o erro (instalação do `.deb` num container Ubuntu 24.04 antes da release).