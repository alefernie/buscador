settings = {
    nop     : 10, // The number of posts per scroll to be loaded
    offset  : 2, // Initial offset, begins at 2 in this case
    error   : 'No More Posts!', // When the user reaches the end this is the message that is
                                // displayed. You can change this if you want.
    delay   : 500, // When you scroll down the posts will load after a delayed amount of time.
                   // This is mainly for usability concerns. You can alter this as you see fit
    scroll  : true, // The main bit, if set to false posts will not load as the user scrolls.
    // but will still load if the user clicks.
    url     : '',   //URL del request
    busy    : false
};

(function($) {

	$.fn.scrollPagination = function(options) {
		
		// Extend the options so they work with the plugin
		if(options) {
			$.extend(settings, options);
		}
		
		// For each so that we keep chainability.
		return this.each(function() {

            if(settings.scroll == true) initmessage = 'Baja para cargar o da clic aquí';
            else initmessage = 'Click for more';
			
			function getData() {

                //var busy = false;

                $this=$("#resultados" + settings.nivel);
                $('#loading-bar' + settings.nivel).remove();
                $this.append("<div class='loading-bar' id='loading-bar" + settings.nivel + "'>" +initmessage+'</div>');

				$.get(settings.url, {
						
					//action        : 'scrollpagination'
				    pagina         : settings.offset

				}, function(data) {
						
					// Change loading bar content (it may have been altered)
                    $('#loading-bar' + settings.nivel).html(initmessage);
						
					// If there is no data returned, there are no more posts to be shown. Show error
					if(data == "") { 
                        $('#loading-bar' + settings.nivel).html(settings.error);
					}
					else {
						
						// Offset increases
					    settings.offset = settings.offset+1;
                        eval("offset."+settings.cat + "=" + settings.offset);
                        $this.append(data);
						
						// No longer busy!	
						settings.busy = false;
					}	
						
				});
					
			}	
			
			//getData(); // Run function initially
            $this=$("#resultados" + settings.nivel);

			// If scrolling is enabled
			if(settings.scroll == true) {
				// .. and the user is scrolling
				$(window).scroll(function() {
                    var $this=$("#resultados" + settings.nivel);
					// Check the user is at the bottom of the element
					if($(window).scrollTop() + $(window).height() > $this.height() && !settings.busy) {
						
						// Now we are working, so busy is true
						settings.busy = true;
						
						// Tell the user we're loading posts
                        $('#loading-bar' + settings.nivel).html('Cargando ...');
						
						// Run the function to fetch the data inside a delay
						// This is useful if you have content in a footer you
						// want the user to see.
						setTimeout(function() {

                            getData();

						}, settings.delay);
							
					}	
				});
			}
			
			// Also content can be loaded by clicking the loading bar/
			$this.find("#resultados" + settings.nivel + '.loading-bar').click(function() {
			
				if(settings.busy == false) {
					settings.busy = true;
					getData();
				}
			
			});
			
		});
	}

})(jQuery);
