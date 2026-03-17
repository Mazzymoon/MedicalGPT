@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM =====================================================
REM MedicalGPT one-click script for Windows + Miniconda + GTX 4060
REM Usage:
REM   run_sft_4060_conda.bat setup
REM   run_sft_4060_conda.bat smoke
REM   run_sft_4060_conda.bat train
REM   run_sft_4060_conda.bat chat
REM =====================================================

set "ENV_NAME=medicalgpt"
set "CUDA_VISIBLE_DEVICES=0"

if "%~1"=="" goto :usage
set "MODE=%~1"

REM ---- Locate conda.bat ----
set "CONDA_BAT="
if defined CONDA_EXE (
  for %%I in ("%CONDA_EXE%") do set "CONDA_EXE_DIR=%%~dpI"
  if exist "%CONDA_EXE_DIR%condabin\conda.bat" set "CONDA_BAT=%CONDA_EXE_DIR%condabin\conda.bat"
  if not defined CONDA_BAT if exist "%CONDA_EXE_DIR%..\condabin\conda.bat" set "CONDA_BAT=%CONDA_EXE_DIR%..\condabin\conda.bat"
)
if not defined CONDA_BAT (
  for /f "delims=" %%I in ('where conda.bat 2^>nul') do (
    if not defined CONDA_BAT set "CONDA_BAT=%%I"
  )
)
if not defined CONDA_BAT if exist "%USERPROFILE%\miniconda3\condabin\conda.bat" set "CONDA_BAT=%USERPROFILE%\miniconda3\condabin\conda.bat"
if not defined CONDA_BAT if exist "%USERPROFILE%\anaconda3\condabin\conda.bat" set "CONDA_BAT=%USERPROFILE%\anaconda3\condabin\conda.bat"

if not defined CONDA_BAT (
  echo [ERROR] conda.bat not found. Please install Miniconda/Anaconda or run from Anaconda Prompt.
  exit /b 1
)

call "%CONDA_BAT%" activate base
if errorlevel 1 (
  echo [ERROR] Failed to activate conda base with: %CONDA_BAT%
  echo [HINT] Try running this script from Anaconda Prompt.
  exit /b 1
)

if /I "%MODE%"=="setup" goto :setup
if /I "%MODE%"=="smoke" goto :smoke
if /I "%MODE%"=="train" goto :train
if /I "%MODE%"=="chat" goto :chat

goto :usage

:setup
cd /d "%~dp0"
echo [INFO] Creating/using conda env: %ENV_NAME%
call conda env list | findstr /R /C:"^%ENV_NAME% " >nul
if errorlevel 1 (
  call conda create -n %ENV_NAME% python=3.10 -y
  if errorlevel 1 (
    echo [ERROR] Failed to create conda env.
    exit /b 1
  )
)
call conda activate %ENV_NAME%
if errorlevel 1 (
  echo [ERROR] Failed to activate env %ENV_NAME%.
  exit /b 1
)
python -m pip install -U pip
python -m pip install -r requirements.txt
if errorlevel 1 (
  echo [ERROR] pip install failed.
  exit /b 1
)
echo [OK] Setup completed.
exit /b 0

:smoke
cd /d "%~dp0"
call conda activate %ENV_NAME%
if errorlevel 1 (
  echo [ERROR] Env %ENV_NAME% not found. Run: %~nx0 setup
  exit /b 1
)
echo [INFO] Running inference smoke test...
python inference.py --base_model Qwen/Qwen2.5-0.5B-Instruct --interactive --load_in_4bit
exit /b %errorlevel%

:train
cd /d "%~dp0"
call conda activate %ENV_NAME%
if errorlevel 1 (
  echo [ERROR] Env %ENV_NAME% not found. Run: %~nx0 setup
  exit /b 1
)
echo [INFO] Training small SFT with QLoRA on GTX 4060...
python supervised_finetuning.py ^
  --model_name_or_path Qwen/Qwen2.5-0.5B-Instruct ^
  --train_file_dir .\data\finetune ^
  --validation_file_dir .\data\finetune ^
  --do_train ^
  --do_eval ^
  --template_name qwen ^
  --use_peft True ^
  --load_in_4bit True ^
  --qlora True ^
  --per_device_train_batch_size 1 ^
  --per_device_eval_batch_size 1 ^
  --gradient_accumulation_steps 8 ^
  --max_train_samples 200 ^
  --max_eval_samples 20 ^
  --model_max_length 512 ^
  --num_train_epochs 1 ^
  --learning_rate 2e-5 ^
  --logging_steps 10 ^
  --eval_steps 50 ^
  --save_steps 100 ^
  --output_dir outputs-sft-4060 ^
  --fp16 True ^
  --bf16 False ^
  --gradient_checkpointing True ^
  --report_to tensorboard
exit /b %errorlevel%

:chat
cd /d "%~dp0"
call conda activate %ENV_NAME%
if errorlevel 1 (
  echo [ERROR] Env %ENV_NAME% not found. Run: %~nx0 setup
  exit /b 1
)
echo [INFO] Chat with base + LoRA adapter...
python inference.py --base_model Qwen/Qwen2.5-0.5B-Instruct --lora_model outputs-sft-4060 --interactive --load_in_4bit
exit /b %errorlevel%

:usage
echo Usage:
echo   %~nx0 setup   ^(create env + install deps^)
echo   %~nx0 smoke   ^(quick inference test^)
echo   %~nx0 train   ^(small SFT training^)
echo   %~nx0 chat    ^(chat with trained LoRA^)
exit /b 1
