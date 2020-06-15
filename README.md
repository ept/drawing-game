Drawing Game
============

On paper, you would play this game as follows: each player starts with an empty
sheet of paper and writes down some word, term, or concept. They pass this to
the neighbouring player, who then needs to draw this term without using
language. They then fold the paper so that the next player can see only the
drawing, but not the words, and pass it to their neighbour, who then in turn
tries to guess the concept from the drawing. Each piece of paper thus collects
alternating word and drawing renderings, with various misunderstandings along
the way likely. When each piece of paper reaches its originator, it is unfolded
to show the sequence of words and drawings, and the result is hopefully
hilarious.

I believe this game is known as
“[Telestrations](https://www.boardgamegeek.com/boardgame/46213/telestrations)”, or even
“[Eat Poop You Cat](https://www.boardgamegeek.com/boardgame/30618/eat-poop-you-cat)”.

This repository contains a web-based implementation of this game, suitable for
video calls with friends and family members during pandemic-imposed lockdown.
If you load the web app on your phone (or other device that has a camera), you
can do your drawings on paper, and then use your phone's camera to upload the
picture.

It's extremely basic: there is no user authentication, and the usability is
pretty rough. But hey, I hacked it together in a few hours, and you can fix it
if you don't like it!

Deployment
----------

The web app is intended to be deployed on [Heroku](https://www.heroku.com/), but
anywhere that runs Ruby should be fine. It requires a PostgreSQL database, whose
tables are automatically created the first time the app starts up. Heroku's
free tier works just fine.

The only tricky bit is image uploads. The app is set up to upload images
directly from the user's web browser to [S3](https://aws.amazon.com/s3/)
(without going via Heroku).
[This reference](https://devcenter.heroku.com/articles/direct-to-s3-image-uploads-in-rails)
is the basis for the image uploading technique I used, and
[this article](https://leonid.shevtsov.me/post/demystifying-s3-browser-upload/)
has useful information on setting up the necessary permissions in the AWS
console.

License
-------

Copyright 2020 Martin Kleppmann. This project is made available under the terms
of the [MIT license](https://opensource.org/licenses/MIT).
