class MonitoringController < ActionController::Base
  def mem
    rss = `ps -o rss= -p #{Process.pid}`.to_i / 1024

    uptime_seconds = (Time.now - Process.clock_gettime(Process::CLOCK_BOOTTIME)).to_i
    uptime = format_duration(uptime_seconds)

    threads = Thread.list.count

    variants_size = `du -sh storage/variants 2>/dev/null`.strip.presence || "N/A"

    attached_count = ActiveStorage::Blob.count
    total_size_bytes = ActiveStorage::Blob.sum(:byte_size)
    total_size_readable = number_to_human_size(total_size_bytes)

    render plain: <<~TEXT
      ✅ Monitoring Status
      -------------------------
      RAM usage:        #{rss} MB
      Uptime:           #{uptime}
      Threads:          #{threads}
      Variants size:    #{variants_size}
      Blobs count:      #{attached_count}
      Blobs total size: #{total_size_readable}
    TEXT
  end

  private

  def format_duration(seconds)
    minutes, secs = seconds.divmod(60)
    hours, mins = minutes.divmod(60)
    days, hrs = hours.divmod(24)
    "%d days, %02d:%02d:%02d" % [days, hrs, mins, secs]
  end

  # Format bytes to human-readable (e.g. 12.3 MB)
  def number_to_human_size(size)
    ApplicationController.helpers.number_to_human_size(size)
  end
end
