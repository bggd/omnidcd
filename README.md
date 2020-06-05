# omnidcd

### Require

- Vim8
- DUB https://github.com/dlang/dub
- DCD 0.12.0 https://github.com/dlang-community/DCD

### Functions

```vim
:call omnidcd#startServer()
:call omnidcd#addPathFromDUBInCurrentDirectory()
```

### EXAMPLE

omnidcd with Vim8 on Windows 10.

example vimrc:

```vim
g:omnidcd_server_cmd = '/Users/foo/AppData/Local/dub/packages/dcd-0.12.0/dcd/bin/dcd-server.exe'
g:omnidcd_client_cmd = '/Users/foo/AppData/Local/dub/packages/dcd-0.12.0/dcd/bin/dcd-client.exe'

g:omnidcd_include_paths = ['/D/dmd2/src/druntime/import', '/D/dmd2/src/phobos']

autocmd FileType d setlocal omnifunc=omnidcd#complete

command! OmniDCD call omnidcd#startServer() | call omnidcd#addPathFromDUBInCurrentDirectory()
```
### Similar

- vim-dutyl https://github.com/idanarye/vim-dutyl
- ncm2-d https://github.com/ncm2/ncm2-d
- deoplete-d https://github.com/landaire/deoplete-d
- ycmd-dcd https://github.com/BitR/ycmd-dcd
