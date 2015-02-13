class IOActors::WriterActor < Concurrent::Actor::RestartingContext

  def initialize io, logger=nil
    @io = io
    @logger = logger
    @writes = []
  end

  def on_message message
    case message
    when IOActors::OutputMessage
      append message.bytes
    when :write
      write
    when :close
      close
    end
  end

  private

  def close
    parent << :close if parent
    @io.close rescue nil
    terminate!
  end

  def append bytes
    @writes.push bytes
    write
  end
    
  # This method will write whatever it can out of the first item in
  # the write queue.  If it can't write it all, it puts the rest back
  def write
    return unless bytes = @writes.shift

    num_bytes = begin
                  @io.write_nonblock(bytes)
                rescue IO::WaitWritable
                  0
                end

    if num_bytes > 0
      @io.flush
    end

    # If the write could not be completed in one go
    if num_bytes < bytes.bytesize
      @writes.unshift bytes.byteslice(num_bytes..bytes.bytesize)
      self << :write
    elsif !@writes.empty?
      self << :write
    end
  rescue IOError, Errno::EPIPE, Errno::ECONNRESET
    close
  end
end
