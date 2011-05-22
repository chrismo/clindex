require 'cl/util/install'

init

$cldir = File.join($siteverdir, 'cl')
$clindexdir = File.join($cldir, 'index')

files = { './cl/index/index.rb' => $clindexdir,
          './cl/index/index.test.rb' => $clindexdir,
          './cl/index.rb' => $cldir
        }

install_lib(files)
