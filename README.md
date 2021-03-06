# omnidcd

### Require

- Vim8
- DUB https://github.com/dlang/dub
- DCD 0.12.0 https://github.com/dlang-community/DCD

### Functions

```vim
omnidcd#startServer()
omnidcd#addPath(paths)
omnidcd#addPathFromDUBInCurrentDirectory()

" for completefunc or omnifunc
omnidcd#complete(findstart, base)
" for tagfunc
omnidcd#tagfunc(pattern, flags, info)
```

### EXAMPLE

omnidcd with Vim8 on Windows 10.

example vimrc:

```vim
let g:omnidcd_server_cmd = '/Users/foo/AppData/Local/dub/packages/dcd-0.12.0/dcd/bin/dcd-server.exe'
let g:omnidcd_client_cmd = '/Users/foo/AppData/Local/dub/packages/dcd-0.12.0/dcd/bin/dcd-client.exe'

let s:include_paths = ['/D/dmd2/src/druntime/import', '/D/dmd2/src/phobos']

autocmd FileType d setlocal omnifunc=omnidcd#complete
autocmd FileType d setlocal tagfunc=omnidcd#tagfunc
command! OmniDCD call omnidcd#startServer() | call omnidcd#addPath(s:include_paths) | call omnidcd#addPathFromDUBInCurrentDirectory()
```
### Similar

- vim-dutyl https://github.com/idanarye/vim-dutyl
- ncm2-d https://github.com/ncm2/ncm2-d
- deoplete-d https://github.com/landaire/deoplete-d
- ycmd-dcd https://github.com/BitR/ycmd-dcd
