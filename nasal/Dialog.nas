#
# Logbook - Add-on for FlightGear
#
# Written and developer by Roman Ludwicki (PlayeRom, SP-ROM)
#
# Copyright (C) 2022 Roman Ludwicki
#
# Logbook is an Open Source project and it is licensed
# under the GNU Public License v3 (GPLv3)
#

#
# Dialog class to display logbook
#
var Dialog = {
    #
    # Constants
    #
    WINDOW_WIDTH         : 1366,
    WINDOW_HEIGHT        : 670,
    PADDING              : 10,
    TXT_WIDTH_MULTIPLIER : 8.5,
    MAX_DATA_ITEMS       : 20,
    SHIFT_Y              : 28,
    COLUMNS_WIDTH        : [
         85, #  0 - date
         50, #  1 - time
        150, #  2 - aircraft
         80, #  3 - callsign
         55, #  4 - from
         55, #  5 - to
         50, #  6 - landings
         50, #  7 - crash
         50, #  8 - day
         50, #  9 - night
         50, # 10 - instrument
         65, # 11 - duration
         65, # 12 - distance
         80, # 13 - fuel
         70, # 14 - max alt
        100, # 15 - note
    ],
    TOTAL_FORMATS        : [
        "%d",   # landings
        "%d",   # crash
        "%.2f", # day
        "%.2f", # night
        "%.2f", # instrument
        "%.2f", # duration
        "%.2f", # distance
        "%.0f", # fuel
        "%.0f", # max alt
    ],
    FONT_NAME            : "LiberationFonts/LiberationSans-Bold.ttf",
    FONT_SIZE            : 12,

    #
    # Constructor
    #
    # File file
    #
    new: func(file) {
        var me = { parents: [Dialog] };

        me.startIndex = 0;

        me.file   = file;
        me.data   = me.file.loadData(me.startIndex, Dialog.MAX_DATA_ITEMS);
        me.totals = me.file.getTotalsData();
        me.style  = me.getStyle().light;
        me.rowTotal = nil;

        me.window = me.crateCanvasWindow();

        me.canvas = me.window.createCanvas().set("background", me.style.CANVAS_BG);
        me.group = me.canvas.createGroup();
        me.vbox = canvas.VBoxLayout.new();
        me.canvas.setLayout(me.vbox);

        me.drawHeaders();
        me.drawScrollGrid();
        me.reDrawGrid();

        me.labelPaging = canvas.gui.widgets.Label.new(me.group, canvas.style, {});
        me.drawBottomBar();

        return me;
    },

    crateCanvasWindow: func() {
        var window = canvas.Window.new([Dialog.WINDOW_WIDTH, Dialog.WINDOW_HEIGHT], "dialog")
            .set("title", "Logbook")
            .setBool("resize", true);

        window.hide();

        window.del = func() {
            # This method will be call after click on (X) button in canvas top
            # bar and here we want hide the window only.
            # FG next version provide destroy_on_close, but for 2020.3.x it's
            # unavailable, so we are handling it manually by this trick.
            call(me.hide, [], me);
        };

        # Because window.del only hide the window, we have to add extra method
        # to really delete the window.
        window.destroy = func() {
            call(canvas.Window.del, [], me);
        };

        return window;
    },

    #
    # Destructor
    #
    del: func() {
        me.window.destroy();
    },

    #
    # Show canvas dialog
    #
    show: func() {
        me.reloadData();
        me.window.show();
    },

    #
    # Hide canvas dialog
    #
    hide: func() {
        me.window.hide();
    },

    #
    # Draw headers row
    #
    drawHeaders: func() {
        var scrollHeaders = canvas.gui.widgets.ScrollArea.new(me.group, canvas.style, {});
        scrollHeaders.setColorBackground(me.style.CANVAS_BG);
        scrollHeaders.setContentsMargins(5 + (Dialog.PADDING * 2), 10, 0, 0); # left, top, right, bottom
        scrollHeaders.setFixedSize(Dialog.WINDOW_WIDTH, 12);
        me.vbox.addItem(scrollHeaders);

        var scrollHeadersContent = scrollHeaders.getContent();
        scrollHeadersContent
            .set("font", Dialog.FONT_NAME)
            .set("character-size", Dialog.FONT_SIZE)
            .set("alignment", "left-baseline");

        var y = Dialog.PADDING * 3;
        var x = Dialog.PADDING * 2;
        var column = 0;
        foreach (var text; me.file.getHeadersData()) {
            me.drawText(scrollHeadersContent, x, 0, me.getReplaceHeaderText(text));
            x += me.getX(column);
            column += 1;
        }
    },

    #
    # Draw scrollArea for logbook data
    #
    drawScrollGrid: func() {
        var scroll = canvas.gui.widgets.ScrollArea.new(me.group, canvas.style, {});
        scroll.setColorBackground(me.style.CANVAS_BG);
        scroll.setContentsMargins(5, 0, 0, 0); # left, top, right, bottom
        me.vbox.addItem(scroll, 1); # 2nd param = stretch
        me.scrollContent = scroll.getContent();
        me.scrollContent
            .set("font", Dialog.FONT_NAME)
            .set("character-size", Dialog.FONT_SIZE)
            .set("alignment", "left-baseline");
    },

    #
    # Draw grid with logbook data
    #
    reDrawGrid: func() {
        # me.scrollContent.setColorFill(me.style.CANVAS_BG); # color of canvas.draw.rectangle
        me.scrollContent.removeAllChildren();

        var y = Dialog.PADDING * 3;
        var index = 0;
        foreach (var row; me.data) {
            var x = Dialog.PADDING * 2;
            var column = 0;

            var rowGroup = me.drawHoverBox(me.scrollContent, y);

            foreach (var text; row) {
                me.drawText(rowGroup, x, 16, text);

                x += me.getX(column);
                column += 1;
            }

            # Draw horizontal line
            # var hr = canvas.draw.rectangle(
            #     me.scrollContent,
            #     Dialog.WINDOW_WIDTH - (Dialog.PADDING * 2), # width
            #     1,                                          # height
            #     Dialog.PADDING,                             # x
            #     y + 10                                      # y
            # );
            # hr.setColor(me.style.GROUP_BG);

            y += Dialog.SHIFT_Y;
            index += 1;
        }

        me.rowTotal = me.drawHoverBox(me.scrollContent, y);
        me.drawTotalsRow(me.rowTotal);

        me.scrollContent.update();
    },

    drawHoverBox: func(cgroup, y) {
        var rowGroup = cgroup.createChild("group");
        rowGroup.setTranslation(Dialog.PADDING, y - Dialog.SHIFT_Y + 11);

        # Create rect because setColorFill on rowGroup doesn't work
        # TODO: Keep the rectangle not too wide, because then you get artifacts in drawing the sliders of ScrollArea.
        var rect = rowGroup.rect(0, 0, Dialog.WINDOW_WIDTH - (Dialog.PADDING * 3), Dialog.SHIFT_Y);
        rect.setColorFill([0.0, 0.0, 0.0, 0.0]);

        MouseHover.new(rowGroup, me.style, rect).addEvents();

        return rowGroup;
    },

    #
    # Draw row with totals summary
    #
    # hash cgroup - Parent canvas group
    #
    drawTotalsRow: func(cgroup) {
        var y = 16;
        var x = Dialog.PADDING * 2 +  me.getX(0) + me.getX(1) + me.getX(2) + me.getX(3) + me.getX(4);
        me.drawText(cgroup, x, y, "Totals:");

        for (var i = 0; i < size(me.totals); i += 1) {
            var total = me.totals[i];
            x += me.getX(i + 5);
            me.drawText(cgroup, x, y, sprintf(Dialog.TOTAL_FORMATS[i], total));
        }

        # Extra bottom margin
        y += Dialog.SHIFT_Y;
        me.drawText(cgroup, x, y, " ");
    },

    #
    # Draw bottom bar with buttons
    #
    drawBottomBar: func() {
        var buttonBox = canvas.HBoxLayout.new();

        var btnFirst = canvas.gui.widgets.Button.new(me.group, canvas.style, {})
            .setText("|<<")
            .setFixedSize(75, 26)
            .listen("clicked", func { me.first(); });

        var btnPrev = canvas.gui.widgets.Button.new(me.group, canvas.style, {})
            .setText("<")
            .setFixedSize(75, 26)
            .listen("clicked", func { me.prev(); });

        me.setPaging();

        var btnNext = canvas.gui.widgets.Button.new(me.group, canvas.style, {})
            .setText(">")
            .setFixedSize(75, 26)
            .listen("clicked", func { me.next(); });

        var btnLast = canvas.gui.widgets.Button.new(me.group, canvas.style, {})
            .setText(">>|")
            .setFixedSize(75, 26)
            .listen("clicked", func { me.last(); });

        buttonBox.addStretch(1);
        buttonBox.addItem(btnFirst);
        buttonBox.addItem(btnPrev);
        buttonBox.addStretch(1);
        buttonBox.addItem(me.labelPaging);
        buttonBox.addStretch(1);
        buttonBox.addItem(btnNext);
        buttonBox.addItem(btnLast);
        buttonBox.addStretch(1);

        # me.vbox.addStretch(1);
        me.vbox.addItem(buttonBox);
        me.vbox.addSpacing(10);
    },

    #
    # Replace some too long header text
    #
    # string text
    # return string
    #
    getReplaceHeaderText: func(text) {
        if (text == "Landings") {
            return "Land.";
        }

        if (text == "Instrument") {
            return "Instr.";
        }

        return text;
    },

    #
    # Get width of column for given index
    #
    # int index
    # return int
    #
    getX: func(index) {
        return Dialog.COLUMNS_WIDTH[index];
    },

    #
    # Get hash with dialog styles
    #
    # return hash
    #
    getStyle: func() {
        return {
            "dark": {
                CANVAS_BG  : "#000000EE",
                # GROUP_BG   : [0.3, 0.3, 0.3],
                TEXT_COLOR : [0.8, 0.8, 0.8],
                HOVER_BG   : [0.2, 0.0, 0.0, 1.0],
            },
            "light": {
                CANVAS_BG  : canvas.style.getColor("bg_color"),
                # GROUP_BG   : [0.7, 0.7, 0.7],
                TEXT_COLOR : [0.3, 0.3, 0.3],
                HOVER_BG   : [1.0, 1.0, 0.5, 1.0],
            },
        };
    },

    #
    # Draw text
    #
    # hash cgroup - Canvas group
    # int x, y - Position of text
    # string text - Text to draw
    #
    drawText: func(cgroup, x, y, text) {
        return cgroup.createChild("text")
            .setTranslation(x, y)
            .setColor(me.style.TEXT_COLOR)
            .setDrawMode(canvas.Text.TEXT)
            .setText(text);
    },

    #
    # Go to first logbook items
    #
    first: func() {
        if (me.startIndex != 0) {
            me.startIndex = 0;
            me.reloadData();
        }
    },

    #
    # Go to previous logbook items
    #
    prev: func() {
        if (me.startIndex - Dialog.MAX_DATA_ITEMS >= 0) {
            me.startIndex -= Dialog.MAX_DATA_ITEMS;
            me.reloadData();
        }
    },

    #
    # Go to next logbook items
    #
    next: func() {
        if (me.startIndex + Dialog.MAX_DATA_ITEMS <= me.file.getTotalLines()) {
            me.startIndex += Dialog.MAX_DATA_ITEMS;
            me.reloadData();
        }
    },

    #
    # Go to last logbook items
    #
    last: func() {
        var old = me.startIndex;
        var pages = math.ceil(me.file.getTotalLines() / Dialog.MAX_DATA_ITEMS);
        me.startIndex = (pages * Dialog.MAX_DATA_ITEMS) - Dialog.MAX_DATA_ITEMS;

        if (old != me.startIndex) {
            me.reloadData();
        }
    },

    #
    # Reload logbook data
    #
    reloadData: func() {
        me.data   = me.file.loadData(me.startIndex, Dialog.MAX_DATA_ITEMS);
        me.totals = me.file.getTotalsData();

        # TODO: reload headers

        me.reDrawGrid();
        me.setPaging();
    },

    setPaging: func() {
        var curPage = (me.startIndex / Dialog.MAX_DATA_ITEMS) + 1;
        var maxPages = math.ceil(me.file.getTotalLines() / Dialog.MAX_DATA_ITEMS);
        me.labelPaging.setText(sprintf("%d / %d (%d items)", curPage, maxPages, me.file.getTotalLines()));
    },
};
