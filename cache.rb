class Cache
  def init
    @threads = []
    @hash = {}
  end

  def set(key, val, time)
    @threads << Thread.new do
      @hash[key] = val.to_a
      sleep(time)
    end
  end

  def get(key)
    $hash[key]
  end
end

