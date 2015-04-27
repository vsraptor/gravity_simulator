require 'green_shoes'
require 'getoptlong'
#The module that provide us with Vector class
require 'matrix'


#This is multiplier when we need to set the scaling factor manually
SCALE_FACTOR = 1e-11
#how many seconds is in a day
DAY = 86400

opts = GetoptLong.new(
	[ '-h', GetoptLong::NO_ARGUMENT ],
  	[ '-f', GetoptLong::REQUIRED_ARGUMENT ],
  	[ '-p', GetoptLong::REQUIRED_ARGUMENT ],
  	[ '-s', GetoptLong::REQUIRED_ARGUMENT ],
  	[ '-t', GetoptLong::REQUIRED_ARGUMENT ],
  	[ '-b', GetoptLong::REQUIRED_ARGUMENT ],
  	[ '-r', GetoptLong::NO_ARGUMENT ],
  	[ '-i', GetoptLong::NO_ARGUMENT ],
)

#default configuration
cfg = {
	:scale => nil,#rely on the program to calculate the correct scale
	:frames => 1200,#how many frames to animate
	:dt => 10 * DAY,#time step 10 days
	:trail => false,#leave a trail .....
	:fps => 15,#frames per second
	:bg => 'black',#background
}


#holds the planet information such us current position, color, mass, acc ... 
class Planet
	attr_accessor :shape, :name, :pos, :old_pos, :mass, :velocity, :acceleration, :scale, :enabled

	def initialize a = {}
		@shoes = a[:app];#reference to the Shoes application
		@enabled = a[:enabled] || true
		@scale = a[:scale] || 1

		@mass = a[:mass] || 1e20
		@distance = a[:distance] || 1e9
		@velocity = a[:velocity] || Vector[0,0]
		@acceleration = a[:acceleration] || Vector[0,0]

		@color = a[:color] || @shoes.black
		@old_pos = Vector[0,0] #used for the trail

		@center_x = a[:center_x]
		@center_y = a[:center_y]

		#setup initial coordinates
		if defined?(a[:pos]) && a[:pos].is_a?(Vector) then
			@pos = a[:pos]
		else
			@pos = Vector[ 0 , @distance ]
		end

		#calculate the planet image drawing radius
		@size = Math.log10(@mass) - 19
		@shoes.nostroke
		@shape = @shoes.oval x,y, @size, :fill => @color
		@name = a[:name]

		@tail = []
		@tail_len = a[:tail_len] || 20
		@tail_color = a[:tail_color] || @color
	end

	#get the distance in meters then scale it to fit into the screen size
	# and because Shoes coordinate zero point is the top left corner we have to account
	# for that. (Green shoes does not support translate method yet)
	def x
		(@pos[0] * @scale) + @center_x
	end
	def y
		(@pos[1] * @scale) + @center_y
	end

	def ox
		(@old_pos[0] * @scale) + @center_x
	end
	def oy
		(@old_pos[1] * @scale) + @center_y
	end

	def draw
		#green Shoes does not draw the oval from the center, so we adjust for that
		@shape.move x - @size, y- @size
	end

	def trail
		@shoes.strokewidth 1
		if defined?(@tail) and @tail.size % @tail_len == 0
			@x = @tail.shift
			@x.remove if @x  #remove furthest part of the tail
		end
		@tmp = @shoes.line ox,oy,x,y, :stroke => @tail_color
		@tail << @tmp
	end

	#used for the tail calculations
	def backup_pos
		@old_pos = @pos.dup
	end

	def dump
		instance_variables.map do |var|
		  puts [var, instance_variable_get(var)].join(":")
		end
	end

end

#Physics computation
class Gravity
	attr_accessor :planets, :app, :trail
	Gravity::G = 6.674e-11 #the gravitational proportionality constant

	def initialize app, a={}
		@shoes = app
		@planets = [] # collect the Planets objects here
		@debug = a[:debug] || false
		@width = a[:width] || 400
		@height = a[:height] || 300
		@scale = a[:scale]

		@bg = a[:bg] || @shoes.black
		@max_distance = 0
		@center_x = @width/2
		@center_y = @height/2

		@i = 0
		@trail = a[:trail] || false
		@trail_segment_step = a[:trail_segment_step] || 3
	end

	#assume the the first element is the star
	def star
		@planets[0]
	end

	#Prepare the Gravity for calculation
	def setup data

		#set the background
		@shoes.background @bg

		unless @scale
			#calculate the scale factor
			@max_distance = data.map { |h| h[:distance] || 0 }.max
			#half the height should be equal to the max distance
			@scale = @height/(2*@max_distance*1.1)
			p ">>scale : #{@scale}" if @debug
		end

		#create the Planet objects
		data.each do |a|
			next if a[:enabled] == false
			a[:app] = @shoes; a[:scale] = @scale
			a[:center_x] = @center_x; a[:center_y] = @center_y
			p = Planet.new a
		   @planets << p
   		p.draw
	   end
	end


	#This the central piece of the whole simulator.. what it does is calculate
	# the velocity change caused by the influence of the remote object (singular)

	def compute_forces (pa,pb,dt)
		#first calculate the distance between the two objects
		r = pa.pos - pb.pos;#vectors
		#Using Gravitation law and Newton second law, find the acceleration imparted on pa
		pa.acceleration = ((- G*pb.mass) / r.magnitude**2) * r.normalize
		# ...now that we know acceleration, do step-calculation of the velocity
		pa.velocity += pa.acceleration * dt
      # ... what is left is to calculate the new position..... from the velocity
	end

	#now that we have the cummulative velocity calculated, find us a new position
	def new_position p,dt
		p.backup_pos if @trail and @i % @trail_segment_step == 0
		p.pos += p.velocity * dt #it happens here
		p.trail if @trail and @i % @trail_segment_step == 0
		p.draw
	end


	#Loop over every object and calculate the influence of all other objects on it
	def compute_all dt
      @i+=1

		@planets.each do |pa|
			@planets.each do |pb|
				unless (pa == pb) #skip if the same obj
					compute_forces pa,pb,dt
				end
			end
			new_position pa, dt
		end
	end
end

#=========================== The UI application =======================
Shoes.app :height => 700, :width => 800 do
#Shoes.app :height => 400, :width => 400 do

	#parse the command line options
	def parse_options opts, cfg
		opts.each do |opt, arg|
		case opt
			when '-h'
				puts "
 -h : help
 -f : total frames to play (def:1200)
 -p : frames per second, dont push it :)
 -s : scale factor to fit the system on the screen, higher value is closer view
      100 will scale you to the inner Solar system
 -t : time step (def: 10 days).
      Smaller value give more accurate results, but is slower.
 -b : background (def: black)
 -r : leave trail ..... you get nice tail marking the path of the planet.
      But if you push it program may become sluggish.
 -i : adjust the scale factor to see the inner Solar system (scale:120,time-step:1)
"
      	exit

			when '-f'
				cfg[:frames] = arg.to_i
				puts "Total frames to play : #{cfg[:frames]}"
			when '-s'
				cfg[:scale] = arg.to_i * SCALE_FACTOR
				puts "Scale : #{cfg[:scale]}"
			when '-t'
				cfg[:dt] = arg.to_i * DAY
				puts "Selected time step: #{cfg[:dt]}"
			when '-r'
				cfg[:trail] = true
				puts "trail...."
			when '-p'
				cfg[:fps] = arg.to_i
				puts "Frames per second: #{cfg[:fps]}"
			when '-i'
				cfg[:dt] = DAY
				cfg[:scale] = 120 * SCALE_FACTOR
				puts "Inner planets ..."
			when '-b'
				cfg[:bg] = arg
				puts "background : #{cfg[:bg]}"
		end #case
		end #opts

	end

	#show a counter of the frames in the top left corner
	def frame_counter num = 0
		if num == 0 #initialize
			stack :width => 80 do
				background white
				@counter = para '0000'
			end
			return
		end
 		@counter.text = sprintf("%04d",num)
	end

   planets = [
   	{ :name => 'Sun', :mass => 1.989e30, :velocity => Vector[0,0], :color => yellow, :pos => Vector[0,0] },
   	{ :name => 'Mercury', :mass => 3.3e23, :velocity => Vector[-47.87e3,0], :color => brown, :distance => 579e8, :tail_len => 10 },
   	{ :name => 'Venus', :mass => 4.869e24, :velocity => Vector[35e3,0], :color => green, :distance => 108.2e9 },
   	{ :name => 'Earth', :mass => 5.973e24, :velocity => Vector[-29.78e3,0], :color => blue, :distance => 149.59e9, :tail_len => 50 },
   	{ :name => 'Mars', :mass => 6.419e23, :velocity => Vector[-24.62e3,0], :color => red, :distance => 227.94e9 },

   	{ :name => 'Ceres', :mass => 9.43e20, :velocity => Vector[-17.88e3,0], :color => red, :distance => 413.69e9 },

  		{ :name => 'Jupiter', :mass => 1.898e27, :velocity => Vector[-13.1e3,0], :color => orange, :distance => 778.54e9 },
  		{ :name => 'Saturn', :mass => 5.685e26, :velocity => Vector[-9.69e3,0], :color => sandybrown, :distance => 1433.4e9 },
  		{ :name => 'Uranus', :mass => 8.681e25, :velocity => Vector[-6.81e3,0], :color => powderblue, :distance => 2876.67e9 },
  		{ :name => 'Neptune', :mass => 1.024e26, :velocity => Vector[-5.43e3,0], :color => cyan, :distance => 4503.4e9 },

  		{ :name => 'Pluto', :mass => 1.30e25, :velocity => Vector[-4.7e3,0], :color => gray, :distance => 5874.0e9 },

   	#{ :name => 'Havoc', :mass => 5.33e28, :velocity => Vector[-12e3,-1e3], :color => red, :distance => 300e9 },
   	#{ :name => 'Postion', :mass => 3.33e25, :velocity => Vector[-11e3,4e3], :color => red, :pos => Vector[100e9,130e9] },

  	]


	#parsing the command line arguments
	parse_options opts, cfg


	#create the Gravity object
	g = Gravity.new self, :width => width, :height => height, :bg => cfg[:bg],
		:trail => cfg[:trail], :debug => false, :scale => cfg[:scale],
		:trail_segment_step => 5

	#prepare all the planets for the computation
   g.setup planets

	frame_counter

	# .... do the animation
	a = animate cfg[:fps] do |i|
		p "------#{i} -------" if @debug
		#compute all gravitational influences
		g.compute_all cfg[:dt]
		#limit the number of frames we want to render
		if i >= cfg[:frames]
			a.stop
			puts "Done."
		end
		frame_counter i
	end

end


__END__


