require 'sinatra'
require 'aws-sdk-s3'
require 'securerandom'

Aws.config.update({
  region: 'eu-west-2',
  credentials: Aws::Credentials.new(ENV['AWS_ACCESS_KEY_ID'], ENV['AWS_SECRET_ACCESS_KEY'])
})

S3_BUCKET = Aws::S3::Resource.new(region: 'eu-west-2').bucket(ENV['S3_BUCKET'])

get '/' do
  @presigned = S3_BUCKET.presigned_post(
    key: "uploads/#{SecureRandom.uuid}/${filename}",
    success_action_status: '201',
    acl: 'public-read',
    content_type: 'image/jpeg'
  )
  erb :index
end

post '/upload' do
  tempfile = params[:file][:tempfile]
  filename = params[:file][:filename]
  FileUtils::Verbose.cp(tempfile.path, "public/uploads/#{filename}")
  'okay'
end

__END__

@@index
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

.image-display img {
  width: 90%;
}
</style>

<form action="<%= @presigned.url %>" enctype="multipart/form-data" method="post" id="upload-form">
  <% @presigned.fields.each do |name, value| %>
    <input type="hidden" name="<%= name %>" value="<%= value %>"/>
  <% end %>
  <p><input name="file" type="file" accept="image/jpeg" capture="environment" id="file-input"/></p>
  <p><input type="submit" value="submit"></p>
</form>

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
        submitButton.prop('disabled', false);
        progressBar.text("Uploading done");
        form.hide();
        const url = $(data.jqXHR.responseXML).find('Location').text();
        $('#image-display').append($("<img />", { src: url }));
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
