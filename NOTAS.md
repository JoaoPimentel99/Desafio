# NOTAS — desafio DevOps

**Situação:** as correções estão no `main`. Tudo foi testado.

## Resumo

- **Lab:** token, permissões, idempotência, reinício do agente, unit, falha escondida, hardening do SSH e limpeza do `rm -rf`. Com o ambiente recriado do zero, o playbook chegou ao estado certo na primeira execução.
- **Só pelo código:** a falha escondida pelo `ignore_errors`.
- **GitHub:** gatilho de fork, release só em tag, release com o `.deb`, versão, lint e actions fixadas. Testado com as tags `v0.0.1-teste1`, `v0.0.1-teste2` e `v0.0.1-teste4`.
- **Máquina de build:** validação de versão, permissão do script e instalação do `.deb` num Ubuntu 24.04 limpo.
- **Não testado:** pull request de fork.
- **Fora do código:** trocar o token da API, porque ele ficou no histórico do Git.

## Parte 1 — Ansible

### Token no repositório e no log
- **Problema:** o token estava escrito em `group_vars/edge.yml` e aparecia no log.
- **Correção:** o token vem da variável `EDGE_AGENT_TOKEN`, com `assert` para falhar se estiver vazio. A task do `.conf` tem `no_log: true`. A task de debug foi removida.
- **Comprovação:** a saída do playbook não mostra o token.
- **Atenção:** apagar o arquivo não basta. **Troque o token na API central.**

### Configuração legível por todos
- **Problema:** o `.conf` tinha permissão `644`. Sem aspas, o YAML lê `644` como número.
- **Correção:** `mode: "0600"`, dono `root`.
- **Comprovação:** `stat` no `edge1` mostrou `600 root:root`.

### Binário copiado com `shell: cp`
- **Problema:** a task sempre aparecia como alterada e não reiniciava o serviço.
- **Correção:** `ansible.builtin.copy` com `notify`.
- **Comprovação:** segunda execução com `changed=0`.

### Configuração alterada não reiniciava o agente
- **Problema:** a task do template não tinha `notify`.
- **Correção:** `notify` no template, no binário e na unit.
- **Comprovação:** mudei o intervalo de 30 para 31 e o agente reiniciou nos três servidores. Depois desfiz a mudança.

### Unit alterada não era recarregada
- **Problema:** era preciso rodar `daemon-reload` na mão.
- **Correção:** `daemon_reload: true` na task e no handler.
- **Comprovação:** mudei a unit, o playbook recarregou o systemd e reiniciou o agente. Depois desfiz a mudança.

### Falha do agente escondida
- **Problema:** `ignore_errors: true` na task que sobe o agente. O playbook passava verde mesmo com o agente parado.
- **Correção:** removido, e adicionada a task "Confirma que o agente continua rodando".
- **Comprovação:** só pelo código. Tentei travar o serviço com `systemctl mask`, mas não funcionou, porque a unit já existe.

### Hardening do SSH nunca era aplicado
- **Problema:**
  1. A condição usava `"ubuntu"`, mas o Ansible informa `"Ubuntu"`. A task era pulada.
  2. Mesmo rodando, as linhas iam para o fim do `sshd_config`. O `50-cloud-init.conf` ligava o login por senha, e ele ganhava.
- **Correção:** a task grava `00-edge-hardening.conf`, que é lido antes, com a condição `'Ubuntu'` e teste com `sshd -t`.
- **Comprovação:** `sshd -T` mostrou `permitrootlogin no` e `passwordauthentication no`.
- **Limite:** `sshd -t` testa só o arquivo novo, não a configuração completa.
- **Atenção:** antes de produção, confirme o login por chave do `deploy` e deixe uma sessão aberta.

### Script que podia apagar o sistema
- **Problema:** `rm -rf $STATE_DIR/*` sem aspas. Se `STATE_DIR` estivesse vazia, virava `rm -rf /*` como root.
- **Correção:** `rm -rf -- "${STATE_DIR:?}"/*`, que aborta se a variável estiver vazia. Corrigi a cópia da role e a cópia do `pacote/`.
- **Comprovação:** `shellcheck` sem avisos nos dois arquivos.
- **Observação:** a cópia do `pacote/` só foi corrigida depois, quando o lint do GitHub apontou o erro.

## Parte 2 — GitHub Actions

### Antes da correção
- **Local:** sem permissão de execução, o script dava `Permission denied`. Com `refs/tags/v1.2.3`, falhava no `sed`.
- **GitHub, `v0.0.1-teste1`:** falhou no lint por causa do `rm -rf` do pacote. O log não abriu, então reproduzi o erro com `shellcheck`.

### Correções extras
- **Permissão do `build-deb.sh`:** o arquivo estava no Git sem o bit de execução. Corrigido no Git e no disco.
- **Cópia do `edge-agent.sh` no `pacote/`:** corrigida junto com o item do `rm -rf`.

### Pull request de fork com acesso a segredos
- **Problema:** `pull_request_target` rodava o código do PR com a chave de assinatura e permissão de escrita.
- **Correção:** `pull_request`, sem `checkout` do código do PR. Permissão de leitura no workflow e escrita só no job de release. O secret `DEB_SIGNING_KEY` saiu, porque nenhum passo usava.
- **Comprovação:** `actionlint` passou. **Não testado** com pull request de fork, porque exige outra conta.

### Release nunca era publicada
- **Problema:** a condição procurava `refs/heads/v`, mas tags são `refs/tags/`.
- **Correção:** `github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')`.
- **Comprovação:** a tag `v0.0.1-teste2` publicou a release.

### Release sem o `.deb`
- **Problema:** o job de release roda em outra máquina e não tinha o arquivo.
- **Correção:** `needs: build` e `download-artifact@v4`.
- **Comprovação:** a release `v0.0.1-teste2` tem o `.deb` anexado.

### Versão errada no pacote
- **Problema:** a versão vinha de `github.ref` (`refs/tags/v1.2.3`), com barras. A expressão colada no `run:` também permitia injeção de comandos.
- **Correção:** um passo calcula a versão por `env`. Tag `vX.Y.Z` vira `X.Y.Z`. Branch ou PR vira `0.0.0+git<sha>`. O `build-deb.sh` recusa versão fora do formato do Debian.
- **Comprovação:**
  - No GitHub, o arquivo saiu como `edge-agent_0.0.1-teste2_all.deb`, sem o `v`.
  - Local: `refs/tags/v1.2.3` foi recusado com `versão inválida`. `1.2.3` gerou o `.deb`.

### Lint que não reprovava
- **Problema:** `continue-on-error: true` no lint.
- **Correção:** removido.
- **Comprovação:** a `v0.0.1-teste1` falhou no lint. A `v0.0.1-teste2` passou.

### Actions apontando para branch
- **Problema:** `@main` muda sem aviso, e o job tem permissão de escrita.
- **Correção:** `@v4`. Não era exigido, mas é boa prática.
- **Comprovação:** a `v0.0.1-teste2` rodou com `@v4` sem erro.
- **Pendente:** fixar o SHA de cada action. Não consegui confirmar o SHA desta versão.

### Título da release
- **Problema:** o título era a mensagem do commit (`v0.0.1-teste2: fix(agente): ...`).
- **Correção:** o nome da tag vai para `--title`, com `--generate-notes`.
- **Comprovação:** a execução #23, na tag `v0.0.1-teste4`, terminou com sucesso em 20s e o título ficou correto.

### Teste do pacote
- **O que fiz:** instalei o `.deb` da `v0.0.1-teste4` num Ubuntu 24.04 limpo, dentro de um container no WSL.
- **O que conferi:** versão `0.0.1-teste4`, arquivos do pacote, execução do agente e heartbeat com `port=9102`. Depois removi o pacote.
- **Não testado:** o serviço com systemd. Isso fica para uma VM.

## Decidi não corrigir

- **`host_key_checking = False`:** deixa o SSH vulnerável a intermediário. Mantido porque o lab não tem `known_hosts`. Em produção, a chave do host precisa estar configurada.
- **`private_key_file = /lab/lab_key`:** caminho do lab. A chave só autentica nos containers do lab.
- **Duas cópias do `edge-agent.sh`:** podem divergir. O ideal é uma fonte só.
- **Caminhos diferentes:** o playbook instala em `/usr/local/bin`, e a unit do pacote usa `/usr/bin`. Próximo passo: usar só o pacote como fonte.
- **`Depends: bash`:** `logger` e `date` já vêm no Ubuntu.
- **Token sem aspas no template:** `$`, espaço ou `#` podem quebrar a leitura. Não testado, fica como risco.
- **SHA das actions:** pendente.

## Parte 3 — Perguntas

1. **Rollout em 30 servidores:** começo com um servidor (`serial: 1`), com `--check --diff` antes. Depois, lotes maiores com `max_fail_percentage: 0`. Sei que deu certo com três checagens: serviço ativo, heartbeat recente e uma segunda execução com `changed=0`. No SSH, deixo uma sessão aberta e testo um login novo antes de fechar a anterior.

2. **Onde fica o token:** num cofre, como Ansible Vault ou um gerenciador de segredos. O controlador lê e envia por SSH. No servidor, fica em `/etc/edge-agent/edge-agent.conf`, com `0600` e dono `root`, sem aparecer no log. Não passo o token na linha de comando, porque ele aparece na lista de processos. O ideal é um token por servidor, com permissão mínima, que dá para trocar.

3. **Release quebrada em 5 servidores:**
   1. Parar o rollout e não publicar mais nada.
   2. Medir o estrago com `systemctl status edge-agent` e `dpkg -l edge-agent`.
   3. Reverter para a versão anterior boa, com `apt-get install edge-agent=<versão>`. Por isso o repositório precisa guardar versões antigas.
   4. Avisar, marcar ou remover a release quebrada. Não reaproveitar a tag.
   5. Corrigir, publicar uma nova versão e fazer postmortem. O teste que teria pego o erro: instalar o `.deb` num Ubuntu 24.04 antes de publicar.
