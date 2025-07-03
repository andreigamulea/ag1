module MemoryLogger
  def self.fetch_memory_usage
    if RUBY_PLATFORM =~ /linux/
      begin
        status = File.read("/proc/self/status")
        if match = status.match(/VmRSS:\s+(\d+)\s+kB/)
          (match[1].to_i / 1024.0).round(2)
        else
          0.0
        end
      rescue => e
        Rails.logger.error("MemoryLogger error: #{e.message}")
        0.0
      end

    elsif RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
      begin
        require 'win32ole'
        wmi = WIN32OLE.connect("winmgmts://")
        processes = wmi.ExecQuery("select * from Win32_Process where ProcessId = #{Process.pid}")
        memory = processes.each.first&.WorkingSetSize.to_i
        (memory / 1024.0 / 1024.0).round(2)
      rescue => e
        Rails.logger.error("MemoryLogger (Windows) error: #{e.message}")
        0.0
      end

    else
      0.0
    end
  end
end
