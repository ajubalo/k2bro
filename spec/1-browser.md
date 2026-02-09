create an application
that is basically a custom browser
with two video player

when it starts, it is 90% of screen leaving a band to the right

it is split vertically in two panes

each pane is split horizontally in two panes

the horizonal and vertical separator can be moved

# left pane: videos

the left pane has two video players
the video players have

- a bar with a pull down with a list of recent videos initially empty, a radio button to select the video,  an icon "lens" to previe, an icon "next" with an arrow, a clock icon and an "x" icon
- the video
- video bar to navigate the video
- a bar showing tags in the form of emoticon

you can select a video clicking on the radio button

you can remove the video from the recents clicking the x

you show the preview clicking on the lens

you go to the next video in the recents clicking on the next arrow to the latest position or the latest tag, right clicking go to the previous, always latest position available

when playing a video check if the dowload interrupts after less than one second in such a case remove the link from recents and warn

you can click on the clock to open recents

# right pane top: browser

the right pane has on top a browser with navigation bar

# right pane bottom: tree

on bottom there is a tree with the levels

reads and write

- website (shows the domain)
  - path (shows the path)
     - link (shows what is in the link after `https://k2s.cc/file/<id>/...` and if it it empty shows the <id>

and a button bar below with the button: "add", "extract", "remove"

if you click on "add" it will add the current site in the browser to the website list if it is not there
and the path, unless it is the home page

if you click remove on a link it will remove it

if you click remove in a path or on a website it will ask confirmation before removal

save the data in the file `data.json` in the specified format

clocking on website or on a path will open the page in the browser

clicking on a link will activate the preview

if you right click on a link it marks as hidden and will not be shown in the list any more, and also removed from the list of the recent videos

add +/- to collapse/expand the tree nodes

# extraction

if you click extract it will look at the text of the current page and will extract all the links starting as http://k2s.cc/file/ and will add it unless it is already there

for each file added it will inke the get info of the file, and add to the list if is_availabe is true,

if the file is already in the list and is not available remove from the list, so you can re-extract to check and update the status

do not change the hidden state

# preview

if you click a link assuming it is in format

`https://k2s.cc/file/<id>/...`

in the browser it will look to

https://static-cache.k2s.cc/sprite/<id>/00.jpeg

and then iterate 01, 02.. until error

then put in the browser an html page showing the images stacked vertically

if there is none will show the actual page

assume each image is a 5x5 grid and generate javascript to that if you click on the iamge calculate the number of the frame by the number of the image and the position in the image

# play the video
if you click on a frame this happens:

- calculate the url to play the video as described in 9-util.py - do not do the challenge if the token is missing ask the user to generate it

- play the video in the current url
- move at the position corrispondend to the frame x 10 seconds

-  add the video to the list of video over the the video

# navigate the video

if the played video and the preview are for the same video you can click on the frame to move in the video

clicking the lens icon will reopen the preview for the current video

you can change video using the pulldown on top of each video it will restore the video at the latest saved position

# save the videos

when you add or change a video
save the url to the played video in a list "recent" with the position the url and the title (the part after fiile/<id>) and it expires after 24 hours

# tagging

clicking on a frame will show the following icons on top of the frame

blo => 💋
dog => 🐕
fro => 😀
bak => 🍑
ass => 🎯
cum => 💦

and round icons of the color with the number

1 Super => red
2 Top => yellow
3 Ok => green
4 Uhm => blue
5 Bad => grey

you can show the icons without navigating to the frame with right click

if you click on the tag it will save a tag with that icon at the frame position

the tag will appear on the tag bar, in a poosition proportional to the position within the video and clicking on the icon will move there

clicking on the colorer icon will give a rating to the video
the icon will appear in the list of links with a background of the rating

the link are ordered showing those rated fist in rating order

tag and rating are saved in data file and shown when you show the file

the tagging popup should appear close to the mouse
and disapper after 3 seconds or if you click on another frame
or you make a selection

right click on the tag on the bar removes it

double click on a frame on the preview will add a blo tag and open the video and also wait until the video is loaded and move to the tagged frame


# self focus and ordering

order the videos on the pull down on top of the videos by priority and the the most recent first
show the priority as backgroound color

if you select a video or a preview from the player bar automatically select that player as the current one

when you tag a previously untagged elemnt gives a priority green

when you preview a previously untagged element gives priority blue

if I tag an element bad do not show in the recent list and in the tree anymore

# local tagging

if I right click on the tag bar show also the tagging popup and add the selected tag at current position of the video

# tags on links

show the tags on the links on the tree, before the name allowing to jump to the video at the tag position

# hide rar
if a file has rar extension ide it


# keep the latest position

keep a counter of the latest position reached, show it in the recents the frame most advanced and show on the button bar a number with a percentage of he video seen, and when the video reaches 90% remove by recents

remove by recents also when the video is 24h old


# hover a preview

if you hover on a tag it will show
while you are hovering
the closest frame of the splites the tag refers

you have to show a clipped image of the corresponding sprite of the image


when you start hovering ensure all the other hover windows are closed
