" .vimrc - Vim 配置

" ==================== 插件管理 ====================
call plug#begin('~/.vim/plugged')
  " 搜尋（核心）
  Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
  Plug 'junegunn/fzf.vim'

  " 編輯輔助
  Plug 'tpope/vim-surround'
  Plug 'tpope/vim-repeat'
  Plug 'tomtom/tcomment_vim'
  Plug 'jiangmiao/auto-pairs'

  " 檔案瀏覽
  Plug 'scrooloose/nerdtree'

  " 外觀
  Plug 'vim-airline/vim-airline'
  Plug 'vim-airline/vim-airline-themes'
  Plug 'luochen1990/rainbow'

  " 語法支援
  Plug 'ekalinin/Dockerfile.vim'
  Plug 'stephpy/vim-yaml'
  Plug 'cespare/vim-toml'
  Plug 'ap/vim-css-color'
call plug#end()

" ==================== 基本設定 ====================
syntax on
set t_Co=256
set encoding=utf-8
set fileencodings=utf-8,cp950
set bg=dark
set clipboard=unnamed

" 行號
set nu
set rnu
set cursorline
set ruler
set showcmd
set scrolloff=3

" 搜尋
set incsearch
set hlsearch
set ignorecase
set smartcase

" 縮排
set ai
set shiftwidth=2
set tabstop=2
set softtabstop=2
set expandtab

" 檔案類型
filetype on
filetype indent on
filetype plugin on

" ==================== 外觀 ====================
let g:airline_theme='badwolf'
let g:airline_powerline_fonts = 1
let g:airline#extensions#tabline#enabled = 1
let g:rainbow_active = 1

" ==================== 快捷鍵 ====================
let mapleader = "\<Space>"

" ESC 替代
inoremap jj <Esc>

" 檔案操作
nnoremap <Leader>w :w<CR>
nnoremap <Leader>q :q<CR>

" 分頁切換
nmap <C-l> gt
nmap <C-h> gT

" FZF
nnoremap <silent> <C-p> :Files<CR>
nnoremap <silent> <Leader>f :Rg<CR>

" NERDTree
nmap <F8> :NERDTreeToggle<CR>

" ==================== 其他 ====================
" 儲存時自動重載 vimrc
autocmd BufWritePost $MYVIMRC source $MYVIMRC
