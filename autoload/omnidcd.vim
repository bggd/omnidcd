if !exists('g:omnidcd_server_cmd')
  let g:omnidcd_server_cmd = 'dcd-server'
end
if !exists('g:omnidcd_client_cmd')
  let g:omnidcd_client_cmd = 'dcd-client'
endif
if !exists('g:omnidcd_include_paths')
  let g:omnidcd_include_paths = []
endif
if !exists('g:omnidcd_dub_cmd')
  let g:omnidcd_dub_cmd = 'dub'
endif

function! s:default_add_complete_item_func(identifier, kind, definition, symbol, documentation) abort
  let l:words = {
        \ 'word': a:identifier,
        \ 'info': a:definition,
        \ 'dup': 1
        \ }
  call complete_add(l:words)
endfunction

if !exists('g:OmniDCDAddCompleteItemFunc')
  let g:OmniDCDAddCompleteItemFunc = function('s:default_add_complete_item_func')
endif

let s:server_is_started = v:false

let s:string_for_stdin = ''
let s:bytepos = 0

let s:client_is_handling_identifiers = v:false
let s:client_is_timeout = v:false

let s:dub_include_paths = {}

function! s:dcd_server_handle(ch, msg) abort
  if !s:server_is_started && match(a:msg, 'Startup completed') > -1
    let s:server_is_started = v:true
  endif
endfunction

function! s:dcd_client_handle(ch, msg) abort
  if s:client_is_handling_identifiers
    let l:info = split(a:msg, '\t')
    call g:OmniDCDAddCompleteItemFunc(
          \ get(l:info, 0, ''),
          \ get(l:info, 1, ''),
          \ get(l:info, 2, ''),
          \ get(l:info, 3, ''),
          \ get(l:info, 4, ''),
          \ )
  elseif a:msg ==# 'identifiers'
    let s:client_is_handling_identifiers = v:true
  endif
endfunction

function! s:dcd_client_stderr(ch, msg) abort
  let s:client_is_timeout = v:true
endfunction

function! s:dub_include_paths_handle(ch, msg) abort
  if isdirectory(a:msg)
    let s:dub_include_paths[a:msg] = 1
  endif
endfunction

function! s:dcd_start_server() abort
  let l:opt = {'callback': function('s:dcd_server_handle')}
  let l:cmd = g:omnidcd_server_cmd
  for i in g:omnidcd_include_paths
    let l:cmd = l:cmd . ' -I' . i
  endfor
  let s:server_is_started = v:false
  let l:job = job_start(l:cmd, l:opt)

  if job_status(l:job) ==# 'fail'
    echoe 'omnidcd#startServer() Error: ' . l:cmd . 'could not run'
    return v:false
  endif

  while job_status(l:job) ==# 'run'
    if s:server_is_started
      break
    endif
    sleep 1m
  endwhile

  return v:true
endfunction

function! s:dcd_complete(findstart, base) abort
  if a:findstart
    let s:client_is_handling_identifiers = v:false
    let s:string_for_stdin =  join(getline(1, '$'))

    let l:text = getline('.')
    let l:start = col('.') - 1

    while l:start > 0 && l:text[start - 1] =~ '\w'
      let l:start -= 1
    endwhile

    let s:bytepos = line2byte(line('.')) - 1 + col('.') - 1
    if s:bytepos < 0
      let s:bytepos = 0
    endif

    if s:dcd_start_server()
      return l:start
    else
      return -2
    endif
  else

    while !s:client_is_handling_identifiers
      let l:opt = {
            \ 'out_cb': function('s:dcd_client_handle'),
            \ 'err_cb': function('s:dcd_client_stderr')
            \ }
      let l:cmd = g:omnidcd_client_cmd . ' -x -c' . s:bytepos

      let l:client_job = job_start(l:cmd, l:opt)
      if job_status(l:client_job) ==# 'fail'
        echoe 'omnidcd#complete() Error: dcd-client could not run'
        return []
      endif

      let l:ch = job_getchannel(l:client_job)
      call ch_sendraw(l:ch, s:string_for_stdin)
      call ch_close_in(l:ch)

      while job_status(l:client_job) ==# 'run'
        if complete_check()
          call job_stop(l:client_job)
          return []
        endif
        sleep 1m
      endwhile

      if s:client_is_timeout
        let s:client_is_timeout = v:false
        continue
      else
        break
      endif
    endwhile

    return []
  endif
endfunction

function! s:dcd_add_path(paths) abort
  if !s:dcd_start_server()
    return
  endif

  let l:cmd = g:omnidcd_client_cmd

  for i in paths
    if isdirectory(i)
      let l:cmd = l:cmd . ' -I' . i
    endif
  endfor

  let l:job = job_start(l:cmd)
  while job_status(l:job) ==# 'run'
    sleep 1m
  endwhile
endfunction

function! s:add_path_from_dub() abort
  if !s:dcd_start_server()
    return
  endif

  let s:dub_include_paths = {}

  let l:opt = {'out_cb': function('s:dub_include_paths_handle')}
  let l:cmd = g:omnidcd_dub_cmd . ' describe --import-paths --vquiet'
  let l:job = job_start(l:cmd, l:opt)
  while job_status(l:job) ==# 'run'
    sleep 1m
  endwhile

  if empty(s:dub_include_paths)
    return
  endif

  call s:dcd_add_path(s:dub_include_paths)
endfunction

function! omnidcd#startServer() abort
  call s:dcd_start_server()
endfunction

function! omnidcd#complete(findstart, base) abort
  return s:dcd_complete(a:findstart, a:base)
endfunction

function! omnidcd#addPath(paths)
  call s:dcd_add_path(a:paths)
endfunction

function! omnidcd#addPathFromDUBInCurrentDirectory() abort
  call s:add_path_from_dub()
endfunction

