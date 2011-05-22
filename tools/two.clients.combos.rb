$LOAD_PATH << '../src'
require 'cl/combogen'
require 'index'

actions = [
  ClIndexLockMgr::LOAD,
  ClIndexLockMgr::SAVE,
  ClIndexLockMgr::EDIT,
  ClIndexLockMgr::READ
]

actions1, actions2 = [], []
actions.each { |s| 
  actions1 << (s.dup + '1')
  actions2 << (s.dup + '2')
}  

args = [actions1, actions2, ['wait', 'no wait']] 
# 1st column is client 1 action
# 2nd column is client 2 action
# 3rd column is client 2 wait (true|false)
f = File.new('combos.txt', File::CREAT|File::TRUNC|File::RDWR)
begin 
  @comboOut = f 
  uniqueProduct(*args)
ensure
  f.close
end  

