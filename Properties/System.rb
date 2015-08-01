﻿# Load required builtins for RGSS
load_assembly 'IronRuby.Libraries', 'IronRuby.StandardLibrary.Zlib'
if $GAME_OS_WIN
	load_assembly 'IronRuby.Libraries', 'IronRuby.StandardLibrary.Win32API'
end
load_assembly 'IronRuby.Libraries', 'IronRuby.StandardLibrary.Threading'
require './System/OpenGame.Runtime.dll'

# Set the cwd to the game data path
Dir.chdir($GAME_DIRECTORY)

# API compatible Thread based Fiber implementation for Ruby 1.8
# https://gist.github.com/tmm1/4631
# (c) 2008 Aman Gupta (tmm1), used with permission

unless defined? Fiber
 
  class FiberError < StandardError
  end
 
  class Fiber
    def initialize
      raise ArgumentError, 'new Fiber requires a block' unless block_given?
 
      @yield = Queue.new
      @resume = Queue.new
 
      @thread = Thread.new{ @yield.push [ *yield(*@resume.pop) ] }
      @thread.abort_on_exception = true
      @thread[:fiber] = self
    end
    attr_reader :thread
 
    def resume *args
      raise FiberError, 'dead fiber called' unless @thread.alive?
      @resume.push(args)
      result = @yield.pop
      result.size > 1 ? result : result.first
    end
    
    def yield *args
      @yield.push(args)
      result = @resume.pop
      result.size > 1 ? result : result.first
    end
    
    def self.yield *args
      raise FiberError, "can't yield from root fiber" unless fiber = Thread.current[:fiber]
      fiber.yield(*args)
    end
 
    def self.current
      Thread.current[:fiber] or raise FiberError, 'not inside a fiber'
    end
 
    def inspect
      "#<#{self.class}:0x#{self.object_id.to_s(16)}>"
    end
  end
end

# Default RGSS globals

class RGSSReset < Exception
end

def rgss_main
	begin
		yield
	rescue RGSSReset
		retry
	end
end

module Kernel
	def load_data(filename)
		File.open(filename, "rb") { |f|
		  obj = Marshal.load(f)
		}
	end

	def save_data(filename)
		File.open(filename, "wb") { |f|
		  Marshal.dump(obj, f)
		}
	end
end

# Script loader

def rgss_start
	filePath = 'Data/Scripts.rxdata' if $RGSS_VERSION == 1
	filePath = 'Data/Scripts.rvdata' if $RGSS_VERSION == 2
	filePath = 'Data/Scripts.rvdata2' if $RGSS_VERSION == 3
    $RGSS_SCRIPTS = []
    unknownScript = 0
   
    # Open the script file
	begin
		script = File.new(filePath, 'r')
	rescue StandardError => error
		p "IO failed: " + $!
	end

    # Gets the array of scripts
    rawData = Marshal.load(script)

    # inflate each script
    rawData.each do |dataArray|
        data = ""
        begin
            data = Zlib::Inflate.inflate(dataArray[2])
        rescue StandardError => error
            data = ""
        end
        
        unless(data.strip.length == 0)
            # Fix up the name
            if(dataArray[1].strip.length == 0)
                dataArray[1] = "Unknown #{unknownScript}"
                unknownScript += 1
            end
        end
		if(data.strip.length > 0) 
			puts "Loaded script: " + dataArray[1]
			$RGSS_SCRIPTS.push([dataArray[0], dataArray[1], dataArray[2], data])
		end
    end
    
	out = ""
	begin
		$RGSS_SCRIPTS.each { |script|
			$0 = script[1];
			rgss_exec script[3], script[1]
		}
	rescue SyntaxError, NameError => boom
		str = "Script compiler error:\n " + boom
		out += str + "\n"
		out += boom.backtrace.join("\n") + "\n"
	rescue StandardError => bang
		str = "Script runtime error:\n " + bang
		out += str + "\n"
		out += bang.backtrace.join("\n") + "\n"
	rescue
		out += "Unknown error happened"
	end
	if(out != "")
		out = out.split(":in `rgss_exec'")[0]
		raise out
	end
end

def rgss_exec(script, scriptname)
	eval(script, nil, scriptname, 0)
end


# Temporary
class Rect
  def to_a
    [self.x, self.y, self.width, self.height]
  end
end

class Plane
  def initialize(v = nil)
    @sprite = Sprite.new(v)
    @bitmap = nil
  end
 
  def dispose
	return if(@sprite.nil?)
	return if(@sprite.disposed?)
	@sprite.bitmap.dispose if(!@sprite.bitmap.nil? && !@sprite.bitmap.disposed?)
	@sprite.dispose
  end
 
  def disposed?
    @sprite.nil? || @sprite.disposed?
  end
 
  def ox=(val)
    @sprite.ox = (val % (@bitmap.nil? ? 1 : @bitmap.width))
  end
 
  def oy=(val)
    @sprite.oy = (val % (@bitmap.nil? ? 1 : @bitmap.height))
  end
 
  def bitmap
    @bitmap
  end
 
  def bitmap=(bmp)
    w, h = vrect.width, vrect.height
   
    nw = bmp.width <= 100 ? 2 : 3
    nh = bmp.height <= 100 ? 2 : 3
   
    dx = [(w / bmp.width).ceil, 1].max * nw
    dy = [(h / bmp.height).ceil, 1].max * nh
 
    bw = dx * bmp.width
    bh = dy * bmp.height
 
    @bitmap = bmp
    @sprite.bitmap.dispose unless @sprite.bitmap.nil? or @sprite.bitmap.disposed?
    @sprite.bitmap = Bitmap.new(bw, bh)
   
    dx.times do |x|
      dy.times do |y|
        @sprite.bitmap.blt(x * bmp.width, y * bmp.height, @bitmap, @bitmap.rect)
      end
    end
  end
 
  def method_missing(sym, *argv, &argb)
    if @sprite.respond_to?(sym)
      return @sprite.send(sym, *argv, &argb)
    end
    super(sym, *argv, &argb)
  end
 
  private
  def vrect
    @sprite.viewport.nil? ? Rect.new(0, 0, Graphics.width, Graphics.height) :
    @sprite.viewport.rect
  end
end