if !exists('g:omnidcd_server_cmd')
  let g:omnidcd_server_cmd = 'dcd-server'
end
if !exists('g:omnidcd_client_cmd')
  let g:omnidcd_client_cmd = 'dcd-client'
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

let s:declarations = []

let s:local_use_bytepos = ''

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

function! s:dcd_symbol_location_handle(ch, msg) abort
  let l:ary = split(a:msg, '\t')
  if filereadable(get(l:ary, 0, ''))
    call add(s:declarations, l:ary)
  endif
endfunction

function! s:dcd_local_use_handle(ch, msg) abort
  if a:msg ==# '00000'
    return
  endif
  let l:ary = split(a:msg, '\t')
  if len(l:ary) > 1
    let s:local_use_bytepos = l:ary[1]
  endif
endfunction

function! s:dcd_start_server() abort
  let l:opt = {'callback': function('s:dcd_server_handle')}
  let l:cmd = g:omnidcd_server_cmd
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

  for i in a:paths
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

  call s:dcd_add_path(keys(s:dub_include_paths))
endfunction

function! s:dcd_tagfunc(pattern, flags, info) abort
  if a:flags !=# 'c'
    return v:null
  endif

  if !s:dcd_start_server()
    return
  endif

  let l:bytepos = line2byte(line('.')) - 1 + col('.') - 1
  if l:bytepos < 0
    let l:bytepos = 0
  endif

  let l:jobs = []

  let s:client_is_timeout = v:false

  let s:declarations = []
  let l:opt = {
        \ 'in_io': 'buffer',
        \ 'in_name': bufname(),
        \ 'out_cb': function('s:dcd_symbol_location_handle'),
        \ 'err_cb': function('s:dcd_client_stderr')
        \ }
  let l:cmd = g:omnidcd_client_cmd . ' --symbolLocation -c' . (l:bytepos + 1)
  call add(l:jobs, job_start(l:cmd, l:opt))

  let s:local_use_bytepos = ''

  let l:opt = {
        \ 'in_io': 'buffer',
        \ 'in_name': bufname(),
        \ 'out_cb': function('s:dcd_local_use_handle'),
        \ 'err_cb': function('s:dcd_client_stderr')
        \ }
  let l:cmd = g:omnidcd_client_cmd . ' --localUse -c' . (l:bytepos + 1)
  let l:job = job_start(l:cmd, l:opt)
  call add(l:jobs, job_start(l:cmd, l:opt))

  while job_status(l:jobs[0]) ==# 'run' || job_status(l:jobs[1]) ==# 'run'
    sleep 1m
  endwhile

  if s:client_is_timeout
    let s:client_is_timeout = v:false
    echom 'omnidcd#tagfunc: DCD Client is timeoutted! Retry a few seconds later'
    return []
  endif

  let l:result = []
  for l:symloc in s:declarations
    call add(l:result, {
          \ 'name': a:pattern,
          \ 'filename': l:symloc[0],
          \ 'cmd': 'go ' . (l:symloc[1] + 1)
          \ })
  endfor

  if empty(l:result) && !empty(s:local_use_bytepos)
    call add(l:result, {
          \ 'name': a:pattern,
          \ 'filename': bufname(),
          \ 'cmd': 'go ' . (s:local_use_bytepos + 1),
          \ })
  endif

  if empty(l:result)
    return v:null
  endif

  return l:result
endfunction

function! omnidcd#startServer() abort
  call s:dcd_start_server()
endfunction

function! omnidcd#complete(findstart, base) abort
  return s:dcd_complete(a:findstart, a:base)
endfunction

function! omnidcd#addPath(paths) abort
  call s:dcd_add_path(a:paths)
endfunction

function! omnidcd#addPathFromDUBInCurrentDirectory() abort
  call s:add_path_from_dub()
endfunction

function! omnidcd#tagfunc(pattern, flags, info) abort
  return s:dcd_tagfunc(a:pattern, a:flags, a:info)
endfunction
