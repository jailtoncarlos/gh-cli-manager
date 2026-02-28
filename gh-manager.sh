#!/usr/bin/env bash
set -euo pipefail

# manage_gh_cli.sh
# Gerencia a instalação e a validação básica do GitHub CLI (`gh`) no ambiente
# local. O script tenta instalar o `gh` quando ele não está presente e oferece
# verificações rápidas de autenticação e acesso ao repositório remoto.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$APP_DIR" || exit 1

DEFAULT_REPO="${GITHUB_REPO:-Prisma-Consultoria/siscan-rpa}"

log() {
  printf '[gh-manager] %s\n' "$*"
}

warn() {
  printf '[gh-manager] aviso: %s\n' "$*" >&2
}

fail() {
  printf '[gh-manager] erro: %s\n' "$*" >&2
  exit 1
}

print_next_steps() {
  cat <<EOF

Proximos passos:
  1. Autenticacao via token:
     bash scripts/dev/manage_gh_cli.sh auth-login token

  2. Autenticacao via web:
     bash scripts/dev/manage_gh_cli.sh auth-login web

  3. Depois valide o acesso ao repositorio:
     bash scripts/dev/manage_gh_cli.sh repo-check

Observacao:
  - Use "token" quando voce tiver GITHUB_TOKEN com acesso ao repositorio.
  - Use "web" quando preferir o fluxo interativo oficial do GitHub CLI.
EOF
}

print_post_login_steps() {
  cat <<EOF

Autenticacao concluida.

Proximo comando sugerido:
  bash scripts/dev/manage_gh_cli.sh repo-check
EOF
}

try_repo_check_after_login() {
  local repo="${1:-$DEFAULT_REPO}"
  log "Tentando validar acesso ao repositorio ${repo}..."
  if gh repo view "$repo"; then
    log "Acesso ao repositorio validado com sucesso."
  else
    warn "Falha ao validar o repositorio ${repo} logo apos o login."
    warn "Execute manualmente: bash scripts/dev/manage_gh_cli.sh repo-check"
  fi
}

usage() {
  cat <<EOF
Uso:
  scripts/dev/manage_gh_cli.sh bootstrap [repo]
  scripts/dev/manage_gh_cli.sh ensure-installed
  scripts/dev/manage_gh_cli.sh status
  scripts/dev/manage_gh_cli.sh auth-login [auto|token|web]
  scripts/dev/manage_gh_cli.sh repo-check [repo]
  scripts/dev/manage_gh_cli.sh issue-list [repo]
  scripts/dev/manage_gh_cli.sh milestone-list [repo]

Comandos:
  bootstrap         Garante instalacao, mostra status do gh e valida acesso ao repo.
  ensure-installed  Instala o GitHub CLI se ele ainda nao estiver presente.
  status            Exibe versao do gh, autenticacao e remote origin local.
  auth-login        Faz login no gh.
                    auto: usa GITHUB_TOKEN se existir; senao cai para login interativo.
                    token: exige token.
                    web: força login interativo via gh auth login.
  repo-check        Valida acesso ao repositorio no GitHub.
  issue-list        Lista as issues abertas do repositorio.
  milestone-list    Lista milestones do repositorio usando a API do gh.

Variaveis opcionais:
  GITHUB_REPO       Repo padrao. Default: ${DEFAULT_REPO}
  GITHUB_TOKEN      Token usado pelo comando auth-login em modo nao interativo.

Como criar um token no GitHub:
  1. Preferir um fine-grained personal access token.
  2. Restringir o token ao repositorio ${DEFAULT_REPO}.
  3. Conceder apenas as permissoes necessarias:
     - Issues: Read and write
     - Pull requests: Read and write
     - Contents: Read and write
     - Metadata: Read-only

Links oficiais:
  - GitHub Docs: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
  - Tela de criacao: https://github.com/settings/personal-access-tokens/new

Quando usar cada forma de login:
  - auth-login token : quando voce tem GITHUB_TOKEN com acesso ao repositorio.
  - auth-login web   : quando prefere autenticar pelo fluxo interativo do gh.
  - auth-login auto  : tenta token primeiro e, se nao houver token, usa login web.
EOF
}

is_command_available() {
  command -v "$1" >/dev/null 2>&1
}

detect_os() {
  local uname_out
  uname_out="$(uname -s 2>/dev/null || echo unknown)"
  case "$uname_out" in
    Linux*)
      echo "linux"
      ;;
    Darwin*)
      echo "macos"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

ensure_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi
  if ! is_command_available sudo; then
    fail "sudo nao esta disponivel para instalar o gh."
  fi
}

install_gh_linux_apt() {
  ensure_sudo
  log "Instalando gh via apt..."
  sudo apt-get update
  sudo apt-get install -y curl ca-certificates
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null 2>&1
  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
    sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y gh
}

install_gh_linux_dnf() {
  ensure_sudo
  log "Instalando gh via dnf..."
  sudo dnf install -y 'dnf-command(config-manager)' || true
  sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
  sudo dnf install -y gh
}

install_gh_linux_yum() {
  ensure_sudo
  log "Instalando gh via yum..."
  sudo yum install -y yum-utils || true
  sudo yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
  sudo yum install -y gh
}

install_gh_macos() {
  if ! is_command_available brew; then
    fail "Homebrew nao encontrado. Instale o brew ou instale o gh manualmente."
  fi
  log "Instalando gh via Homebrew..."
  brew install gh
}

ensure_installed() {
  if is_command_available gh; then
    log "gh ja esta instalado: $(gh --version | head -n 1)"
    return 0
  fi

  log "gh nao encontrado. Tentando instalar..."
  case "$(detect_os)" in
    linux)
      if is_command_available apt-get; then
        install_gh_linux_apt
      elif is_command_available dnf; then
        install_gh_linux_dnf
      elif is_command_available yum; then
        install_gh_linux_yum
      else
        fail "Nao encontrei gerenciador suportado (apt, dnf ou yum) para instalar o gh."
      fi
      ;;
    macos)
      install_gh_macos
      ;;
    *)
      fail "Sistema operacional nao suportado para instalacao automatica do gh."
      ;;
  esac

  if ! is_command_available gh; then
    fail "Instalacao do gh nao concluiu com sucesso."
  fi

  log "gh instalado com sucesso: $(gh --version | head -n 1)"
  print_next_steps
}

show_status() {
  if is_command_available gh; then
    log "gh: $(gh --version | head -n 1)"
    if gh auth status >/dev/null 2>&1; then
      log "autenticacao gh: ok"
      gh auth status
    else
      warn "autenticacao gh: nao autenticado"
      gh auth status || true
      print_next_steps
    fi
  else
    warn "gh nao esta instalado"
  fi

  if git remote get-url origin >/dev/null 2>&1; then
    log "remote origin: $(git remote get-url origin)"
  else
    warn "remote origin nao configurado neste repositorio"
  fi
}

prompt_for_token() {
  printf 'Cole o GITHUB_TOKEN (entrada oculta): '
  read -r -s GITHUB_TOKEN_INPUT
  printf '\n'
  if [ -z "$GITHUB_TOKEN_INPUT2" ]; then
    fail "nenhum token informado. Consulte os links do --help para criar um token."
  fi
  GITHUB_TOKEN="$GITHUB_TOKEN_INPUT"
  export GITHUB_TOKEN
}

auth_login_with_token() {
  ensure_installed

  if [ -z "${GITHUB_TOKEN:-}" ]; then
    prompt_for_token
  fi

  log "Executando login nao interativo com GITHUB_TOKEN..."
  printf '%s' "$GITHUB_TOKEN" | gh auth login --hostname github.com --git-protocol https --with-token
  print_post_login_steps
  try_repo_check_after_login
}

auth_login_web() {
  ensure_installed
  log "Executando login interativo no gh..."
  gh auth login
  print_post_login_steps
  try_repo_check_after_login
}

auth_login() {
  local mode="${1:-auto}"
  case "$mode" in
    auto)
      if [ -n "${GITHUB_TOKEN:-}" ]; then
        auth_login_with_token
      else
        warn "GITHUB_TOKEN nao definido. Caindo para login interativo do gh."
        auth_login_web
      fi
      ;;
    token)
      auth_login_with_token
      ;;
    web)
      auth_login_web
      ;;
    *)
      fail "modo de login invalido: ${mode}. Use auto, token ou web."
      ;;
  esac
}

repo_check() {
  local repo="${1:-$DEFAULT_REPO}"
  ensure_installed
  log "Validando acesso ao repositorio ${repo}..."
  gh repo view "$repo"
}

issue_list() {
  local repo="${1:-$DEFAULT_REPO}"
  ensure_installed
  log "Listando issues abertas de ${repo}..."
  gh issue list --repo "$repo"
}

milestone_list() {
  local repo="${1:-$DEFAULT_REPO}"
  ensure_installed
  log "Listando milestones de ${repo}..."
  gh api "repos/${repo}/milestones"
}

bootstrap() {
  local repo="${1:-$DEFAULT_REPO}"
  ensure_installed
  show_status
  if gh auth status >/dev/null 2>&1; then
    repo_check "$repo"
  else
    warn "Pulando validacao do repositorio porque o gh ainda nao esta autenticado."
    print_next_steps
  fi
}

main() {
  local command="${1:-bootstrap}"
  case "$command" in
    bootstrap)
      bootstrap "${2:-$DEFAULT_REPO}"
      ;;
    ensure-installed)
      ensure_installed
      ;;
    status)
      show_status
      ;;
    auth-login)
      auth_login "${2:-auto}"
      ;;
    repo-check)
      repo_check "${2:-$DEFAULT_REPO}"
      ;;
    issue-list)
      issue_list "${2:-$DEFAULT_REPO}"
      ;;
    milestone-list)
      milestone_list "${2:-$DEFAULT_REPO}"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      fail "comando invalido: ${command}"
      ;;
  esac
}

main "$@"
