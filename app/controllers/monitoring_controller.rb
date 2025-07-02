require 'sys/proctable'
include Sys

class MonitoringController < ActionController::Base
  def mem
    process = ProcTable.ps.find { |p| p.pid == Process.pid }

    rss_mb = if Gem.win_platform?
  process&.working_set_size.to_i / (1024 * 1024)
else
  process&.rss.to_i / 1024
end


    uptime_seconds = (Time.now - ::APP_BOOT_TIME).to_i


    uptime = format_duration(uptime_seconds)

    threads = Thread.list.count
    variants_size = `du -sh storage/variants 2>/dev/null`.strip.presence || "N/A"

    attached_count = ActiveStorage::Blob.count
    total_size_bytes = ActiveStorage::Blob.sum(:byte_size)
    total_size_readable = number_to_human_size(total_size_bytes)

    render plain: <<~TEXT
      ✅ Monitoring Status
      -------------------------
      RAM usage:        #{rss_mb} MB
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

  def number_to_human_size(size)
    ApplicationController.helpers.number_to_human_size(size)
  end
end
