#!/usr/bin/env bash
set -euo pipefail

REPORT_FILE="vdi_ai_assessment_report_$(date +%Y%m%d_%H%M%S).md"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

section() {
  echo "" >> "$REPORT_FILE"
  echo "## $1" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
}

subsection() {
  echo "" >> "$REPORT_FILE"
  echo "### $1" >> "$REPORT_FILE"
  echo "" >> "$REPORT_FILE"
}

code_block_start() {
  echo '```' >> "$REPORT_FILE"
}

code_block_end() {
  echo '```' >> "$REPORT_FILE"
}

write_cmd_output() {
  local title="$1"
  shift
  subsection "$title"
  code_block_start
  {
    echo "\$ $*"
    echo ""
    "$@" 2>&1 || true
  } >> "$REPORT_FILE"
  code_block_end
}

write_text() {
  echo "$1" >> "$REPORT_FILE"
}

safe_cat_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    cat "$file"
  else
    echo "Arquivo não encontrado: $file"
  fi
}

get_total_mem_gb() {
  awk '/MemTotal/ {printf "%.2f GB\n", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "N/A"
}

get_root_disk_size() {
  df -h / 2>/dev/null | awk 'NR==2 {print $2 " total / " $4 " livre"}' || echo "N/A"
}

gpu_summary() {
  if command_exists nvidia-smi; then
    nvidia-smi --query-gpu=name,memory.total,driver_version,cuda_version --format=csv,noheader 2>/dev/null || true
  else
    lspci 2>/dev/null | grep -Ei 'vga|3d|display' || true
  fi
}

virtualization_summary() {
  if command_exists systemd-detect-virt; then
    systemd-detect-virt || echo "none"
  elif command_exists virt-what; then
    virt-what || echo "none"
  else
    echo "Ferramenta de detecção de virtualização não encontrada"
  fi
}

ai_capability_note() {
  local mem_gb raw_mem
  raw_mem=$(awk '/MemTotal/ {print $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "0")
  mem_gb=$(printf "%.0f" "$raw_mem" 2>/dev/null || echo "0")

  echo "- **Observações automáticas iniciais:**" >> "$REPORT_FILE"

  if command_exists nvidia-smi; then
    echo "  - GPU NVIDIA detectada. A máquina pode ser candidata para inferência local e possivelmente fine-tuning leve, dependendo da VRAM disponível." >> "$REPORT_FILE"
  else
    echo "  - Nenhuma GPU NVIDIA detectada via \`nvidia-smi\`. Isso sugere foco em CPU, uso remoto de APIs, modelos pequenos ou aceleração via infraestrutura externa." >> "$REPORT_FILE"
  fi

  if [[ "$mem_gb" -ge 64 ]]; then
    echo "  - RAM >= 64 GB: cenário bom para processamento de dados, embeddings, vetores, RAG, inferência local de modelos pequenos/médios e experimentação robusta." >> "$REPORT_FILE"
  elif [[ "$mem_gb" -ge 32 ]]; then
    echo "  - RAM entre 32 GB e 63 GB: cenário razoável para embeddings, RAG e inferência local de modelos menores." >> "$REPORT_FILE"
  elif [[ "$mem_gb" -ge 16 ]]; then
    echo "  - RAM entre 16 GB e 31 GB: viável para pipelines leves, ETL, embeddings e uso de modelos compactos." >> "$REPORT_FILE"
  else
    echo "  - RAM < 16 GB: forte limitação para IA local. Melhor priorizar APIs externas, automações, análise de dados e modelos muito pequenos." >> "$REPORT_FILE"
  fi

  echo "  - Este parecer é preliminar; a decisão final depende especialmente de: **VRAM, número de vCPUs, storage livre, restrições de segurança, acesso à internet, Docker/Podman e políticas corporativas**." >> "$REPORT_FILE"
}

# Cabeçalho
cat > "$REPORT_FILE" <<EOF
# Relatório técnico da VDI para avaliação de soluções de IA

**Data de geração:** $(date '+%Y-%m-%d %H:%M:%S %Z')  
**Hostname:** $(hostname 2>/dev/null || echo "N/A")  
**Usuário:** $(whoami 2>/dev/null || echo "N/A")

Este relatório foi gerado automaticamente para apoiar a avaliação da capacidade da máquina VDI para uso em soluções de IA, incluindo inferência local, pipelines de dados, embeddings, RAG, uso de containers, bibliotecas Python, aceleração por GPU e integração com infraestrutura corporativa.

---

## Resumo executivo

- **Sistema operacional:** $(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "N/A")
- **Kernel:** $(uname -r 2>/dev/null || echo "N/A")
- **Arquitetura:** $(uname -m 2>/dev/null || echo "N/A")
- **CPU:** $(lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' || echo "N/A")
- **vCPUs/CPUs lógicas:** $(nproc 2>/dev/null || echo "N/A")
- **Memória total:** $(get_total_mem_gb)
- **Disco raiz:** $(get_root_disk_size)
- **Virtualização:** $(virtualization_summary)
- **GPU:** $(gpu_summary | head -n 1 | sed 's/^/- /' || echo "- N/A")

EOF

ai_capability_note

section "Sistema operacional"
write_cmd_output "Release do sistema" safe_cat_file /etc/os-release
write_cmd_output "Kernel e arquitetura" uname -a
write_cmd_output "Uptime" uptime

section "CPU e processamento"
write_cmd_output "Resumo da CPU" lscpu
write_cmd_output "Detalhes da CPU via /proc/cpuinfo" bash -c "cat /proc/cpuinfo | sed -n '1,80p'"
write_cmd_output "Carga atual" bash -c "uptime && echo && cat /proc/loadavg"

section "Memória"
write_cmd_output "Uso de memória" free -h
write_cmd_output "Informações detalhadas de memória" bash -c "cat /proc/meminfo | sed -n '1,80p'"
if command_exists dmidecode; then
  write_cmd_output "DMI / memória física (pode exigir sudo)" sudo dmidecode -t memory
else
  subsection "DMI / memória física"
  write_text "Comando \`dmidecode\` não encontrado."
fi

section "Disco e filesystem"
write_cmd_output "Espaço em disco" df -hT
write_cmd_output "Dispositivos de bloco" lsblk -o NAME,FSTYPE,SIZE,TYPE,MOUNTPOINT,MODEL
if command_exists mount; then
  write_cmd_output "Pontos de montagem" mount
fi

section "GPU e aceleração"
write_cmd_output "Dispositivos PCI relacionados a vídeo" bash -c "lspci | grep -Ei 'vga|3d|display'"

if command_exists nvidia-smi; then
  write_cmd_output "GPU NVIDIA - resumo" nvidia-smi
  write_cmd_output "GPU NVIDIA - query detalhada" nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free,memory.used,utilization.gpu,temperature.gpu,cuda_version --format=csv
else
  subsection "GPU NVIDIA"
  write_text "Comando \`nvidia-smi\` não encontrado."
fi

if command_exists nvcc; then
  write_cmd_output "CUDA compiler" nvcc --version
else
  subsection "CUDA compiler"
  write_text "Comando \`nvcc\` não encontrado."
fi

if command_exists rocminfo; then
  write_cmd_output "ROCm info" rocminfo
fi

section "Virtualização e contexto da VDI"
write_cmd_output "Detecção de virtualização" bash -c 'systemd-detect-virt 2>/dev/null || virt-what 2>/dev/null || echo "Não foi possível detectar"'
write_cmd_output "Informações DMI do sistema (pode exigir sudo)" sudo dmidecode -t system
write_cmd_output "Sessão gráfica / display" bash -c 'echo "XDG_SESSION_TYPE=$XDG_SESSION_TYPE"; echo "DISPLAY=$DISPLAY"; echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"'

section "Rede e conectividade"
write_cmd_output "Interfaces de rede" ip addr
write_cmd_output "Rotas" ip route
write_cmd_output "DNS resolv.conf" safe_cat_file /etc/resolv.conf
write_cmd_output "Hostname e resolução" hostnamectl
write_cmd_output "Teste de conectividade básica" bash -c 'ping -c 2 8.8.8.8 || true; echo; ping -c 2 google.com || true'

section "Ferramentas de desenvolvimento"
write_cmd_output "Python" bash -c 'python3 --version || python --version || true'
write_cmd_output "Pip" bash -c 'pip3 --version || pip --version || true'
write_cmd_output "Git" git --version
write_cmd_output "GCC" bash -c 'gcc --version | head -n 5'
write_cmd_output "Make" make --version

if command_exists java; then
  write_cmd_output "Java" java -version
fi

section "Ambiente Python para IA"
write_cmd_output "Pacotes Python instalados (filtrados)" bash -c '
PYTHON_BIN=$(command -v python3 || command -v python || true)
if [[ -n "$PYTHON_BIN" ]]; then
  "$PYTHON_BIN" -m pip list 2>/dev/null | grep -Ei "torch|tensorflow|jax|transformers|accelerate|sentence-transformers|spacy|scikit|numpy|pandas|faiss|chromadb|llama|vllm|onnx|xgboost|lightgbm" || true
else
  echo "Python não encontrado"
fi
'

write_cmd_output "Informações detalhadas do Python" bash -c '
PYTHON_BIN=$(command -v python3 || command -v python || true)
if [[ -n "$PYTHON_BIN" ]]; then
  "$PYTHON_BIN" - <<PY
import platform
import sys
print("Executable:", sys.executable)
print("Version:", sys.version)
print("Platform:", platform.platform())
PY
else
  echo "Python não encontrado"
fi
'

section "Containers e execução isolada"
if command_exists docker; then
  write_cmd_output "Docker version" docker --version
  write_cmd_output "Docker info" docker info
else
  subsection "Docker"
  write_text "Docker não encontrado."
fi

if command_exists podman; then
  write_cmd_output "Podman version" podman --version
  write_cmd_output "Podman info" podman info
else
  subsection "Podman"
  write_text "Podman não encontrado."
fi

section "Bibliotecas e runtime úteis para IA"
write_cmd_output "Bibliotecas compartilhadas relevantes" bash -c "ldconfig -p 2>/dev/null | grep -Ei 'cuda|cudnn|nccl|openblas|mkl|onnx|tensorrt' || true"
write_cmd_output "Variáveis de ambiente relevantes" bash -c "env | grep -Ei 'cuda|cudnn|python|venv|conda|proxy|http_proxy|https_proxy|no_proxy|ssl|cert' | sort || true"

section "Processos e uso atual"
write_cmd_output "Top processos por memória" bash -c "ps aux --sort=-%mem | head -n 20"
write_cmd_output "Top processos por CPU" bash -c "ps aux --sort=-%cpu | head -n 20"

section "Segurança, permissões e restrições"
write_cmd_output "SELinux" getenforce
write_cmd_output "Firewall" bash -c 'firewall-cmd --state 2>/dev/null || systemctl status firewalld --no-pager 2>/dev/null || true'
write_cmd_output "Sudo disponível?" bash -c 'sudo -n true && echo "sudo sem senha disponível" || echo "sudo requer senha ou não disponível"'

section "Conclusão preliminar automatizada"
write_text "Abaixo, um parecer automático inicial com base nos dados coletados."
ai_capability_note

section "Checklist de avaliação para soluções de IA"
cat >> "$REPORT_FILE" <<'EOF'
- **Inferência local de LLMs pequenos:** depende principalmente de RAM, CPU e eventual GPU.
- **Embeddings e RAG:** normalmente viáveis mesmo sem GPU, desde que exista memória e storage razoáveis.
- **Fine-tuning / treino:** geralmente inviável em VDI comum sem GPU dedicada suficiente.
- **Uso de APIs externas:** depende de política de rede, proxy, certificados corporativos e compliance.
- **Containers (Docker/Podman):** muito úteis para padronizar ambiente, mas às vezes bloqueados em ambiente corporativo.
- **GPU pass-through em VDI:** precisa ser validado; muitas VDIs mostram vídeo, mas não expõem aceleração útil para IA.
- **Modelos sensíveis / dados corporativos:** exigem avaliação de segurança, isolamento, auditoria e governança.
EOF

echo ""
echo "Relatório gerado com sucesso em: $REPORT_FILE"
