module MemoryLogger
  def self.fetch_memory_usage
    if RUBY_PLATFORM =~ /linux/
      rss_kb = `ps -o rss= -p #{Process.pid}`.to_i
      (rss_kb / 1024.0).round(2)
    elsif RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
      require 'win32ole'
      wmi = WIN32OLE.connect("winmgmts://")
      processes = wmi.ExecQuery("select * from Win32_Process where ProcessId = #{Process.pid}")
      memory = processes.each.first&.WorkingSetSize.to_i
      (memory / 1024.0 / 1024.0).round(2)
    else
      0.0
    end
  end
end
