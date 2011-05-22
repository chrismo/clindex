require 'ftools'
require 'cl/util/file'
require 'cl/util/version'

module CLabs
  module Index
    VERSION = CLabs::Version.new(1, 1, 0)

    def do_system(cmd)
      puts cmd if ARGV.include?('-v')
      system(cmd)
    end

    def do_build
      ver = VERSION.to_s
      namever = "clindex.#{ver}"
      zipfn = "#{namever}.zip"
      dl_url = "dl/clindex/#{zipfn}"
      File.makedirs("./#{namever}/cl/index")
      File.copy '../inst/install.rb', "./#{namever}"
      File.copy '../src/index.rb', "./#{namever}/cl/index"
      File.copy '../src/index.test.rb', "./#{namever}/cl/index"
      File.copy '../cl/index.rb', "./#{namever}/cl"
      ClUtilFile.delTree("../dist") if File.exists? "../dist"
      File.makedirs('../dist')
      system("zip -r ../dist/#{zipfn} ./#{namever}")
      ClUtilFile.delTree("./#{namever}")

      puts "updating scrplist.xml..."
      fsize = (File.size("../dist/#{zipfn}") / 1000).to_s + 'k'
      require 'f:/dev/cvslocal/cweb/clabs/scrplist.rb'
      slist = get_slist
      slist.groups.each do |group|
        group.items.each do |sitem|
          if sitem.name =~ /clIndex/
            sitem.version = VERSION.to_s
            sitem.date = Time.now.strftime("%m/%d/%Y")
            dl = sitem.downloads[0]
            dl.name = zipfn
            dl.link = dl_url
            dl.size = fsize
          end
        end
      end
      write_slist(slist)

      puts "copying .zip to clabs dist..."
      cp_dest_dir = "f:/dev/cvslocal/cweb/clabs/bin/dl/clindex"
      File.makedirs(cp_dest_dir)
      File.copy "../dist/#{zipfn}", File.join(cp_dest_dir, "#{zipfn}")
      do_system('pause')
    end
  end
end

if __FILE__ == $0
  include CLabs::Index
  do_build
end