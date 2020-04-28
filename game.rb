require 'sinatra'
require 'aws-sdk-s3'
require 'securerandom'
require 'sequel'

Aws.config.update({
  region: 'eu-west-2',
  credentials: Aws::Credentials.new(ENV['AWS_ACCESS_KEY_ID'], ENV['AWS_SECRET_ACCESS_KEY'])
})

S3_BUCKET = Aws::S3::Resource.new(region: 'eu-west-2').bucket(ENV['S3_BUCKET'])

DB = Sequel.connect(ENV['DATABASE_URL'])

DB.create_table? :games do
  primary_key :id
  String :name
end

DB.create_table? :players do
  primary_key :id
  foreign_key :game_id, :games, null: false, index: true
  String :name
end

DB.create_table? :answers do
  primary_key :id
  foreign_key :in_reply_to, :answers, null: true,  index: true
  foreign_key :game_id,     :games,   null: false, index: true
  foreign_key :player_id,   :players, null: false
  Integer     :round,                 null: false
  String      :answer
  unique [:player_id, :round]
end

helpers do
  def h(text)
    Rack::Utils.escape_html(text)
  end
end

get '/' do
  erb :index
end

post '/games' do
  DB[:games].insert(name: params[:name])
  redirect to('/')
end

get '/games/:game_id' do
  @players = DB[:players].where(game_id: params[:game_id]).order(:id).all
  @first_round = DB[:answers].where(game_id: params[:game_id], round: 1).order(:player_id).all
  erb :game
end

post '/players' do
  DB[:players].insert(game_id: params[:game_id], name: params[:name])
  redirect to("/games/#{params[:game_id].to_i}")
end

get '/players/:player_id' do
  @player = DB[:players].first(id: params[:player_id])
  @my_answers = DB[:answers].where(game_id: @player[:game_id], player_id: params[:player_id]).order(:round).all
  if @my_answers.empty?
    redirect to("/players/#{@player[:id]}/rounds/1")
  else
    erb :player
  end
end

get '/players/:player_id/rounds/:round' do
  @player = DB[:players].first(id: params[:player_id])
  @my_answer = DB[:answers].first(
    game_id:   @player[:game_id],
    player_id: params[:player_id],
    round:     params[:round]
  )

  if @my_answer
    @prev_answer = DB[:answers].first(id: @my_answer[:in_reply_to]) if @my_answer[:in_reply_to]
    @predecessor = DB[:players].first(id: @prev_answer[:player_id]) if @prev_answer
  else
    # Determine previous and next players in the ring
    @players = DB[:players].where(game_id: @player[:game_id]).order(:id).all
    my_index = @players.find_index {|p| p[:id] == params[:player_id].to_i }
    @predecessor = @players[my_index - 1]
    @successor = @players[(my_index + 1) % @players.size]

    @prev_answer = DB[:answers].first(
      game_id:   @player[:game_id],
      player_id: @predecessor[:id],
      round:     params[:round].to_i - 1
    )

    @presigned = S3_BUCKET.presigned_post(
      key: "uploads/#{SecureRandom.uuid}/${filename}",
      success_action_status: '201',
      acl: 'public-read',
      content_type: 'image/jpeg'
    )
  end
  erb :round
end

post '/answers' do
  DB[:answers].insert(
    in_reply_to: params[:in_reply_to],
    game_id:     params[:game_id],
    player_id:   params[:player_id],
    round:       params[:round],
    answer:      params[:answer]
  )
  redirect to("/players/#{params[:player_id].to_i}/rounds/#{params[:round].to_i + 1}")
end

get '/games/:game_id/threads/:initiator_id' do
  @players = DB[:players].where(game_id: params[:game_id]).all.inject({}) do |players, player|
    players[player[:id]] = player[:name]
    players
  end
  @answers = DB[:answers].where(game_id: params[:game_id]).all
  @thread = @answers.filter {|answer| answer[:player_id] == params[:initiator_id].to_i && answer[:round] == 1 }

  while true
    last_id = @thread.last[:id]
    reply = @answers.detect {|answer| answer[:in_reply_to] == last_id }
    break if reply.nil?
    @thread << reply
  end
  erb :thread
end

__END__

@@index
<!DOCTYPE html>
<meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
<ul>
<% DB[:games].order(:id).each do |game| %>
  <li><a href="/games/<%= h game[:id] %>"><%= h game[:name] %></a></li>
<% end %>
</ul>
<form action="/games" method="post">
  <p><label for="name">New game:</label><br>
  <input type="text" id="name" name="name" size="20"></p>
  <p><input type="submit" value="submit"></p>
</form>

@@game
<!DOCTYPE html>
<meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
<h3><%= h DB[:games].where(id: params[:game_id]).get(:name) %></h3>
<p>Players:</p>
<ul>
<% @players.each do |player| %>
  <li><a href="/players/<%= h player[:id] %>"><%= h player[:name] %></a></li>
<% end %>
</ul>
<% if @first_round.empty? %>
  <form action="/players" method="post">
    <input type="hidden" name="game_id" value="<%= h params[:game_id] %>">
    <p><label for="name">New player:</label><br>
    <input type="text" id="name" name="name" size="20"></p>
    <p><input type="submit" value="submit"></p>
  </form>
<% else %>
  <p>Game threads:</p>
  <ul>
    <% @first_round.each do |answer| %>
      <li><a href="/games/<%= h params[:game_id] %>/threads/<%= h answer[:player_id] %>">Thread
        started by <%= h @players.filter {|p| p[:id] == answer[:player_id] }.first[:name] %></li>
    <% end %>
  </ul>
<% end %>

@@player
<!DOCTYPE html>
<meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
<h3>Hello <%= h @player[:name] %>!</h3>
<p>These are your answers so far:</p>
<ul>
<% @my_answers.each do |answer| %>
  <li><a href="/players/<%= h @player[:id] %>/rounds/<%= h answer[:round] %>">Round <%= h answer[:round] %></a></li>
<% end %>
<li><a href="/players/<%= h @player[:id] %>/rounds/<%= h(@my_answers.last[:round] + 1) %>">Play next round</a></li>
</ul>

@@round
<!DOCTYPE html>
<meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
<script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.5.0/jquery.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.12.1/jquery-ui.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/blueimp-file-upload/10.13.1/js/jquery.fileupload.min.js"></script>

<style>
.progress {
  max-width: 600px;
  margin:    0.2em 0 0.2em 0;
}

.progress .bar {
  height:  1.2em;
  padding-left: 0.2em;
  color:   white;
  display: none;
}

#image-display img {
  width: 90%;
}
</style>

<h3>Hello <%= h @player[:name] %>!</h3>

<% if @prev_answer %>
  <% if @prev_answer[:round].odd? %>
    <p><%= h @predecessor[:name] %> wrote:</p>
    <p><em><%= h @prev_answer[:answer] %></em></p>
  <% else %>
    <p><%= h @predecessor[:name] %> drew:</p>
    <p><img src="<%= h @prev_answer[:answer] %>" style="width: 100%"></p>
  <% end %>
<% end %>

<% if @my_answer %>
  <% if @prev_answer %>
    <p>In round <%= h @my_answer[:round] %>, you interpreted this as:</p>
  <% else %>
    <p>You started the game with:</p>
  <% end %>
  <% if @my_answer[:round].odd? %>
    <p><em><%= h @my_answer[:answer] %></em></p>
  <% else %>
    <p><img src="<%= h @my_answer[:answer] %>" style="width: 100%"></p>
  <% end %>
<% elsif @prev_answer || params[:round].to_i == 1 %>
  <% if params[:round].to_i == 1 %>
    <p>Please think of something that <%= h @successor[:name] %> should draw.</p>
  <% elsif params[:round].to_i.odd? %>
    <p>What do you think that is supposed to represent?</p>
  <% else %>
    <p>Now it's your turn to draw it!</p>
  <% end %>
  <form action="/answers" method="post" id="answer-form">
    <input type="hidden" name="game_id" value="<%= h @player[:game_id] %>">
    <input type="hidden" name="player_id" value="<%= h @player[:id] %>">
    <input type="hidden" name="round" value="<%= h params[:round] %>">
    <% if @prev_answer %>
      <input type="hidden" name="in_reply_to" value="<%= h @prev_answer[:id] %>">
    <% end %>
    <% if params[:round].to_i.odd? %>
      <p><input type="text" id="answer" name="answer" size="40"></p>
      <p><input type="submit" value="submit"></p>
    <% else %>
      <input type="hidden" id="answer" name="answer" value="">
    <% end %>
  </form>
  <% if params[:round].to_i.even? %>
    <form action="<%= @presigned.url %>" enctype="multipart/form-data" method="post" id="upload-form">
      <% @presigned.fields.each do |name, value| %>
        <input type="hidden" name="<%= name %>" value="<%= value %>"/>
      <% end %>
      <p><input name="file" type="file" accept="image/jpeg" capture="environment" id="file-input"/></p>
      <p><input type="submit" value="submit"></p>
    </form>
  <% end %>
  <p>You're in round <%= h params[:round] %> of game <%= h DB[:games].where(id: @player[:game_id]).get(:name) %>.</p>
<% else %>
  <p>Waiting for <%= h @predecessor[:name] %> to come up with something.</p>
<% end %>

<div id="image-display"></div>

<script>
// Based on https://devcenter.heroku.com/articles/direct-to-s3-image-uploads-in-rails
$(function() {
  $('#upload-form').find('input:file').each(function(i, elem) {
    const fileInput    = $(elem);
    const form         = $(fileInput.parents('form:first'));
    const submitButton = form.find('input[type="submit"]');
    const progressBar  = $('<div class="bar"></div>');
    const barContainer = $('<div class="progress"></div>').append(progressBar);
    fileInput.after(barContainer);

    fileInput.fileupload({
      fileInput: fileInput,
      url: form.data('url'),
      type: 'POST',
      autoUpload: true,
      formData: form.data('form-data'),
      paramName: 'file',
      dataType: 'XML',
      replaceFileInput: false,

      progressall: function (e, data) {
        var progress = parseInt(data.loaded / data.total * 100, 10);
        progressBar.css('width', progress + '%')
      },

      start: function (e) {
        submitButton.prop('disabled', true);
        progressBar.
          css('background', 'green').
          css('display', 'block').
          css('width', '0%').
          text("Loading...");
      },

      done: function(e, data) {
        progressBar.text("Uploading done");
        form.hide();
        const url = $(data.jqXHR.responseXML).find('Location').text();
        $('#image-display').append($("<img />", { src: url, style: 'width: 100%' }));
        $('#answer').val(url);
        $('#answer-form').submit();
      },

      fail: function(e, data) {
        submitButton.prop('disabled', false);
        progressBar.
          css("background", "red").
          text("Failed");
      }
    });
  });
});
</script>

@@thread
<!DOCTYPE html>
<meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
<p>This thread was started by <%= h @players[@thread.first[:player_id]] %>, who wrote:</p>
<p><em><%= h @thread.first[:answer] %></em></p>
<% @thread.slice(1, @thread.size - 1).each do |answer| %>
  <p><%= h @players[answer[:player_id]] %> interpreted this as:</p>
  <% if answer[:round].odd? %>
    <p><em><%= h answer[:answer] %></em></p>
  <% else %>
    <p><img src="<%= h answer[:answer] %>" width="100%"></p>
  <% end %>
<% end %>
