#!/bin/bash
set -e  # Exit immediately in case of error

printf "\033]0;Installer\007"
clear
rm -f *.bat  

# Function to log messages with timestamps
log_message() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg"
}

# function to check and install Homebrew (only for macOS)
check_install_homebrew() {
    if [ "$(uname)" = "Darwin" ]; then
        if ! command -v brew >/dev/null 2>&1; then
            log_message "Homebrew not found. Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
                log_message "Failed to install Homebrew. Exiting."
                exit 1
            }
            log_message "Homebrew installed successfully."
            export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"  # Adapt PATH for different architectures (Intel/ARM)
        else
            log_message "Homebrew is already installed."
        fi
    fi
}

# Function to find a suitable Python version
find_python() {
    for py in python3.10 python3 python; do
        if command -v "$py" > /dev/null 2>&1; then
            echo "$py"
            return
        fi
    done
    log_message "No compatible Python installation found. Please install Python 3.7+."
    exit 1
}

# Function to install FFmpeg based on the distribution
install_ffmpeg() {
    if command -v apt > /dev/null; then
        log_message "Installing FFmpeg using apt..."
        sudo apt update && sudo apt install -y ffmpeg
    elif command -v pacman > /dev/null; then
        log_message "Installing FFmpeg using pacman..."
        sudo pacman -Syu --noconfirm ffmpeg
    elif command -v dnf > /dev/null; then
        log_message "Installing FFmpeg using dnf..."
        sudo dnf install -y ffmpeg --allowerasing || install_ffmpeg_flatpak
    elif command -v brew > /dev/null; then
        log_message "Installing FFmpeg using Homebrew..."
        brew install ffmpeg
    else
        log_message "Unsupported distribution for FFmpeg installation. Trying Flatpak..."
        install_ffmpeg_flatpak
    fi
}

install_python_ffmpeg() {
    log_message "Installing python-ffmpeg..."
    python -m pip install python-ffmpeg
}

# Function to create or activate a virtual environment
prepare_install() {
    if [ -d ".venv" ]; then
        log_message "Virtual environment found. This implies Applio has been already installed or this is a broken install."
        printf "Do you want to execute run-applio.sh? (Y/N): " >&2
        read -r r
        r=$(echo "$r" | tr '[:upper:]' '[:lower:]')
        if [ "$r" = "y" ]; then
            chmod +x run-applio.sh
            ./run-applio.sh && exit 0
        else
            log_message "Continuing with the installation."
            rm -rf .venv
            create_venv
        fi
    else
        create_venv
    fi
}

# Function to create the virtual environment and install dependencies
create_venv() {
    log_message "Creating virtual environment..."
    py=$(find_python)

    "$py" -m venv .venv

    log_message "Activating virtual environment..."
    source .venv/bin/activate

    # Install pip if necessary and upgrade
    log_message "Ensuring pip is installed..."
    python -m ensurepip --upgrade || {
        log_message "ensurepip failed, attempting manual pip installation..."
        curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
        python get-pip.py
    }
    python -m pip install --upgrade pip

    install_ffmpeg
    install_python_ffmpeg

    log_message "Installing dependencies..."
    if [ -f "requirements.txt" ]; then
        python -m pip install -r requirements.txt
    else
        log_message "requirements.txt not found. Please ensure it exists."
        exit 1
    fi

    log_message "Installing PyTorch..."
    python -m pip install torch==2.3.1 torchvision==0.18.1 torchaudio==2.3.1 --upgrade --index-url https://download.pytorch.org/whl/cu121

    finish
}

# Function to finish installation
finish() {
    log_message "Verifying installed packages..."
    if [ -f "requirements.txt" ]; then
        installed_packages=$(python -m pip freeze)
        while IFS= read -r package; do
            expr "${package}" : "^#.*" > /dev/null && continue
            package_name=$(echo "${package}" | sed 's/[<>=!].*//')
            if ! echo "${installed_packages}" | grep -q "${package_name}"; then
                log_message "${package_name} not found. Attempting to install..."
                python -m pip install --upgrade "${package}"
            fi
        done < "requirements.txt"
    else
        log_message "requirements.txt not found. Please ensure it exists."
        exit 1
    fi

    clear
    echo "Applio has been successfully installed. Run the file run-applio.sh to start the web interface!"
    exit 0
}

if [ "$(uname)" = "Darwin" ]; then
    log_message "Detected macOS..."
    check_install_homebrew
    brew install python@3.10
    export PYTORCH_ENABLE_MPS_FALLBACK=1
    export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
    export PATH="/opt/homebrew/bin:$PATH"
elif [ "$(uname)" != "Linux" ]; then
    log_message "Unsupported operating system. Are you using Windows?"
    log_message "If yes, use the batch (.bat) file instead of this one!"
    exit 1
fi

prepare_install
