require "sinatra"
require "sinatra/reloader"
require "sinatra/content_for"
require "tilt/erubis"
require "yaml"
require "bcrypt"

configure do #this is telling Sinatra
  enable :sessions
  set :sessions_secret, 'secret'
  set :erb, :escape_html => true
end
#----------------------

#-------CLASSES--------
class Log
  attr_reader :human_history, :computer_history

  def initialize
    @human_history = []
    @computer_history = []
  end

  def update(human_move, computer_move) #Only sending .value here, not a Move object
    @human_history << human_move.value
    @computer_history << computer_move.value
  end

  def count(element)
    @human_history.count(element)
  end 

  def each
    @human_history.each_with_index do |symbol, index|
      yield(symbol, @computer_history[index])
    end
  end
end


class Move
  VALUES = ['rock', 'paper', 'scissors'].freeze

  WINNING_COMBINATION = {
    'rock' => 'scissors',
    'paper' => 'rock',
    'scissors' => 'paper'
  }.freeze

  LOSING_COMBINATION = {
    'rock' => 'paper',
    'paper' => 'scissors',
    'scissors' => 'rock'
  }.freeze

  attr_reader :value

  def initialize(value)
    @value = value
  end

  def >(other_move)
    WINNING_COMBINATION[@value].include?(other_move.value)
  end

  def <(other_move)
    LOSING_COMBINATION[@value].include?(other_move.value)
  end

  def to_s
    @value
  end

end


class Computer #Dirty, but working
  def self.johnny_move(history)
    #"rock"
    hash = {}
    Move::VALUES.each do |move|
      hash[move] = history.count(move)
    end
    symbol = self.sample_of_best(hash)
    
  end

  def self.hal_move(history)
    current_history = history.human_history
    return move = Move::VALUES.sample if current_history.empty?
    last_move = current_history.last
    possible_winning_moves = []
    possible_winning_moves << Move::LOSING_COMBINATION[last_move]
    move = possible_winning_moves.sample
    move
  end

  def self.blue_move(history)
    if history.computer_history.length.zero?
      move = Move::VALUES.sample
    else
      hash = self.winning_percentages(history)
      rand = self.random(10)
      move = self.sample_of_best(hash) if rand < 8
      move = Move::VALUES.sample if rand >= 8
    end
    move
  end

  private

  def self.winning_percentages(history)
    winning_symbols = self.find_winning_symbols(history)
    percentage_hash = self.find_win_percent(winning_symbols, history)
    percentage_hash
  end

  def self.random(max_num)
    (1..max_num).to_a.sample
  end

  def self.sample_of_best(hash)
    maximum = hash.max_by { |_, v| v }
    array = []
    hash.each do |k, v|
      if v == maximum.last
        array << k
      end
    end
    array.sample
  end

  def self.find_winning_symbols(history)
    total_games = history.computer_history.length
    winning_symbol = []
    index = 0
    while index < total_games
      computer_past_move = Move.new(history.computer_history[index])
      human_past_move = Move.new(history.human_history[index])
      if computer_past_move > human_past_move
        winning_symbol << history.computer_history[index]
      end
      index += 1
    end
    winning_symbol
  end

  def self.find_win_percent(winning_symbols, history)
    total_games = history.computer_history.length
    hash = Hash.new(0)
    Move::VALUES.each do |symbol|
      hash[symbol] = winning_symbols.count(symbol)
    end
    hash.each do |key, value|
      hash[key] = if value.positive?
                    value.to_f / total_games
                  else
                    0
                  end
    end
    hash
  end

end
#----------------------

#-------HELPERS--------
helpers do
  def display_result(human_move, computer_move)
    if human_move > computer_move
      "#{session[:user]} wins!"
    elsif computer_move > human_move
      "#{session[:ai]} wins!"
    else
      "It's a tie."
    end
  end

  def display_history(human_move, computer_move)
    if Move.new(human_move) > Move.new(computer_move)
      "<strong>#{human_move}</strong> v <del>#{computer_move}</del>"
    elsif Move.new(computer_move) > Move.new(human_move)
      "<del>#{human_move}</del> v <strong>#{computer_move}</strong>"
    else
      "#{human_move} v #{computer_move}"
    end
  end

  def display_hall(entry)
    if entry["score"] == 1
      word = "win"
    else
      word = "wins"
    end
    "<li>#{entry["name"]} - #{entry["score"]} #{word} (vs. #{entry["opponent"]})</li>"
  end
end
#----------------------

#-------METHODS--------
def load_users
  path = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yaml", __FILE__)
  else
    File.expand_path("../data/users.yaml", __FILE__)
  end
  YAML.load_file(path)
end

def load_fame
  path = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/hall_of_fame.yaml", __FILE__)
  else
    File.expand_path("../data/hall_of_fame.yaml", __FILE__)
  end
  YAML.load_file(path)
end

def update_hall(username, winning_streak, computer_name)
  hall = load_fame
  new_entry = {"name" => username, "score" => winning_streak, "opponent" => computer_name}
  insert_index = case 
                 when winning_streak > hall[0]["score"]
                  0
                 when winning_streak > hall[1]["score"]
                  1
                 else
                  2
                 end
  hall.insert(insert_index, new_entry)
  hall.delete_at(3)
  File.open("data/hall_of_fame.yaml", "w") do |f|
    f.write(hall.to_yaml)
  end
end

def reset_hall 
  path = File.expand_path("../data/default_hall_of_fame.yaml", __FILE__)
  hall = YAML.load_file(path)


  File.open("data/hall_of_fame.yaml", "w") do |f|
    f.write(hall.to_yaml)
  end
end

def enter_hall?(winning_streak)
  hall = load_fame
  lowest_score = hall[2]["score"]
  winning_streak > lowest_score
end

def valid_credentials?(username, password)
  users = load_users
  if users.key?(username) && BCrypt::Password.new(users[username]) == password
    true
  else
    false
  end
end

def result(human_move, computer_move)
  if human_move > computer_move
    :human
  elsif computer_move > human_move
    :computer
  else
    :tie
  end
end

def valid_newuser?(username, password)
  if username.strip.size < 1 || username.strip.size > 20
    "Username must be between 1 and 20 characters in length."
  elsif password.size < 5
    "Password must be at least 5 characters in length."
  end
end

def ai_move(log, ai_name) #Need LOGIC
  case ai_name
  when "Johnny 5"
    Computer.johnny_move(log)
  when "Deep Blue"
    Computer.blue_move(log)
  when "HAL"
    Computer.hal_move(log)
  end
end
#----------------------

#-------ROUTES---------
get "/" do
  @content = File.read("data/intro.txt")
  session[:user] = nil unless session[:user]
  erb :homepage
end

get "/users/logout" do
  erb :logout
end

get "/hall_of_fame" do
  @hall = load_fame
  erb :hall_of_fame
end

get "/signin" do
  erb :signin
end

get "/newuser" do
  erb :newuser
end

get "/about" do
  @content = File.read("data/about.txt")
  erb :about
end

post "/users/newuser" do

  username = params[:username].strip
  password = params[:password]
  error = valid_newuser?(username, password)
  if error
    session[:message] = error
    erb :"/newuser"
  else
    encrypted_password = BCrypt::Password.create(password)
    users = load_users
    users[username] = encrypted_password

    File.open("data/users.yaml", "r+") do |f|
      f.write(users.to_yaml)
    end
    session[:user] = username
    redirect "/opponents/select"
  end
end

post "/users/signin" do
  username = params[:username]
  password = params[:password]

  if valid_credentials?(username, password)
    session[:user] = username
    redirect "/opponents/select"
  else
    session[:message] = "Please try again."
    status 422
    erb :signin
  end
end

get "/opponents/select" do
  session[:human] = 0
  session[:computer] = 0
  session[:tie] = 0
  session[:log] = Log.new
  session[:winning_streak] = 0
  unless session[:user]
    session[:user] = "Guest"
  end
  @ai_list = ["Johnny 5", "Deep Blue", "HAL"]
  session[:message] = "Signed in as #{session[:user]}."
  erb :select_ai
end

post "/:ai_name/select" do
  session[:ai] = params[:ai_name]
  redirect "/select_throw"
end

get "/select_throw" do
  @log = session[:log]
  @move_list = Move::VALUES
  session[:message] = "Signed in as #{session[:user]}."
  erb :select_throw
end

post "/human_move/:move" do
  session[:human_move] = Move.new(params[:move])
  session[:computer_move] = Move.new(ai_move(session[:log], session[:ai]))

  redirect "/result"
end

get "/result" do
  winner = result(session[:human_move], session[:computer_move])
  if winner == :human
    session[:winning_streak] += 1
  elsif winner == :computer
    if enter_hall?(session[:winning_streak])
      total_streak = session[:winning_streak]
      session[:hall] = "You've been entered into the Hall of Fame with a total winning streak of #{total_streak}!"
      update_hall(session[:user], session[:winning_streak], session[:ai])
    end
    session[:winning_streak] = 0
  end
  session[:log].update(session[:human_move], session[:computer_move])
  session[winner] += 1
  @log = session[:log]
  erb :result
end

post "/reset_hall" do
  unless session[:user] == "admin"
    session[:message] = "Log in as Admin to reset the Hall of Fame"
    redirect "/hall_of_fame"
  else
    reset_hall
    redirect "/hall_of_fame"
  end
end