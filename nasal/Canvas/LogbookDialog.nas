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
# LogbookDialog class to display logbook
#
var LogbookDialog = {
    #
    # Constants
    #
    WINDOW_WIDTH         : 1120,
    WINDOW_HEIGHT        : 680,
    TXT_WIDTH_MULTIPLIER : 8.5,
    MAX_DATA_ITEMS       : 20,
    COLUMNS_WIDTH        : [
         85, #  0 - date
         50, #  1 - time
        150, #  2 - aircraft
         80, #  3 - aircraft type
         80, #  4 - callsign
         55, #  5 - from
         55, #  6 - to
         50, #  7 - landings
         50, #  8 - crash
         50, #  9 - day
         50, # 10 - night
         50, # 11 - instrument
         65, # 12 - duration
         65, # 13 - distance
         80, # 14 - fuel
         70, # 15 - max alt
        100, # 16 - note
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
    TOTALS_COLUMNS_SHIFT : 6,
    FONT_NAME            : "LiberationFonts/LiberationSans-Bold.ttf",
    FONT_SIZE            : 12,

    #
    # Constructor
    #
    # hash file - File object
    # hash filters - Filters object
    # return me
    #
    new: func(file, filters) {
        var me = {
            parents : [
                LogbookDialog,
                Dialog.new(Dialog.ID_LOGBOOK, LogbookDialog.WINDOW_WIDTH, LogbookDialog.WINDOW_HEIGHT, "Logbook"),
            ],
            file    : file,
            filters : filters,
        };

        me.addonNodePath = me.addon.node.getPath();

        me.setPositionOnCenter();

        # Override window del method for close FilterSelector
        var self = me;
        me.window.del = func() {
            call(LogbookDialog.hide, [], self);
        };

        me.startIndex = 0;

        me.file.loadAllData();

        me.data           = [];
        me.totals         = me.file.getTotalsData();
        me.rowTotal       = nil;
        me.headersContent = nil;
        me.dataContent    = nil;

        me.canvas.set("background", me.style.CANVAS_BG);
        me.detailsDialog  = DetailsDialog.new(file);
        me.helpDialog     = HelpDialog.new();
        me.aboutDialog    = AboutDialog.new();
        me.filterSelector = FilterSelector.new();

        me.listView = ListView.new(
            me.group,
            me.vbox,
            ListView.SHIFT_Y * 22, # 22 = 20 items + 1 headers + 1 totals
            LogbookDialog.WINDOW_WIDTH,
            LogbookDialog.COLUMNS_WIDTH,
            ListView.LAYOUT_H
        );
        me.listView.setTranslation(0, 20);
        me.listView.setClickDialog(me.detailsDialog);
        me.listView.setStyle(me.style);
        me.listView.setFont(LogbookDialog.FONT_NAME, LogbookDialog.FONT_SIZE);

        me.drawHeaders();

        me.labelPaging = canvas.gui.widgets.Label.new(me.group, canvas.style, {});
        me.btnStyle    = canvas.gui.widgets.Button.new(me.group, canvas.style, {});
        me.drawBottomBar();

        me.listeners = [];

        append(
            me.listeners,
            setlistener(me.addonNodePath ~ "/addon-devel/reload-logbook", func(node) {
                me.reloadLogbookListenerCallback(node);
            })
        );

        append(me.listeners, setlistener(me.addonNodePath ~ "/addon-devel/redraw-logbook", func(node) {
            if (node.getValue()) {
                # Back to false
                setprop(node.getPath(), false);

                me.redraw(false);
            }
        }));

        return me;
    },

    #
    # Callback from "/addons/by-id/org.flightgear.addons.logbook/addon-devel/reload-logbook" listener
    #
    # hash node - Node object
    # return void
    #
    reloadLogbookListenerCallback: func(node) {
        if (node.getValue()) {
            # Back to false
            setprop(node.getPath(), false);

            if (getprop(me.addonNodePath ~ "/addon-devel/logbook-entry-deleted") == true) {
                setprop(me.addonNodePath ~ "/addon-devel/logbook-entry-deleted", false);

                # Check index of last page
                var pages = math.ceil(me.file.getTotalLines() / LogbookDialog.MAX_DATA_ITEMS);
                var newIndex = (pages * LogbookDialog.MAX_DATA_ITEMS) - LogbookDialog.MAX_DATA_ITEMS;
                if (me.startIndex > newIndex) {
                    # We exceed the maximum index, so set a new one
                    me.startIndex = newIndex;
                }

                me.reloadData();

                # User deleted entry, hide details window
                me.detailsDialog.hide();
                me.detailsDialog.parentDataIndex = nil;
                me.detailsDialog.listView.parentDataIndex = nil;
            }
            else {
                # Reload after edit data
                me.reloadData();
                me.detailsDialog.reload();
            }
        }
    },

    #
    # Destructor
    #
    # return void
    #
    del: func() {
        foreach (var listener; me.listeners) {
            removelistener(listener);
        }

        me.detailsDialog.del();
        me.helpDialog.del();
        me.aboutDialog.del();
        me.filterSelector.del();
        call(Dialog.del, [], me);
    },

    #
    # Show canvas dialog
    #
    # return void
    #
    show: func() {
        me.reloadData(false);
        call(Dialog.show, [], me);
    },

    #
    # Hide canvas dialog
    #
    # return void
    #
    hide: func() {
        me.filterSelector.hide();
        me.detailsDialog.hide();
        call(Dialog.hide, [], me);
    },

    #
    # Draw headers row
    #
    # return void
    #
    drawHeaders: func() {
        me.headersContent = me.group.createChild("group");
        me.headersContent.setTranslation(0, 0);
        me.headersContent
            .set("font", LogbookDialog.FONT_NAME)
            .set("character-size", LogbookDialog.FONT_SIZE)
            .set("alignment", "left-baseline");

        me.reDrawHeadersContent();
    },

    #
    # Draw headers row
    #
    # return void
    #
    reDrawHeadersContent: func() {
        me.headersContent.removeAllChildren();

        var y = ListView.PADDING * 3;
        var x = ListView.PADDING * 3;
        var column = 0;
        var headers = me.file.getHeadersData();
        foreach (var text; headers) {
            if (column == size(headers) - 1) {
                # Don't show Note column
                break;
            }

            var rowGroup = me.headersContent.createChild("group");
            rowGroup.setTranslation(x, 0);
            var rect = rowGroup.rect(0, 0, me.listView.getX(column), ListView.SHIFT_Y);
            rect.setColorFill([0.0, 0.0, 0.0, 0.0]);

            me.drawText(rowGroup, 0, 20, me.getReplaceHeaderText(column, text));

            me.setMouseHoverHeadersListener(
                rowGroup,
                rect,
                me.filters.getFilterItemsByColumnIndex(column),
                me.filters.getFilerTitleByColumnIndex(column),
                column
            );

            x += me.listView.getX(column);
            column += 1;
        }
    },

    #
    # hash rowGroup - canvas group
    # hash rect - rectangle canvas object
    # vector items|nil - Items for FilterSelector
    # string title|nil - FilterSelector title dialog
    # int index|nil - Column index as File.INDEX_[...]
    # return void
    #
    setMouseHoverHeadersListener: func(rowGroup, rect, items, title, index) {
        if (items == nil or title == nil or index == nil) {
            # No filters for this column, skip it
            return;
        }

        rowGroup.addEventListener("mouseenter", func {
            rect.setColorFill(me.style.HOVER_BG);
        });

        rowGroup.addEventListener("mouseleave", func {
            rect.setColorFill([0.0, 0.0, 0.0, 0.0]);
        });

        rowGroup.addEventListener("click", func(event) {
            me.filterSelector.setItems(items);
            me.filterSelector.setColumnIndex(index);
            me.filterSelector.setPosition(event.screenX, event.screenY);
            me.filterSelector.setTitle(title);
            me.filterSelector.setCallback(me, me.filterSelectorCallback);
            me.filterSelector.show();
        });
    },

    #
    # int filterId
    # string value
    # return void
    #
    filterSelectorCallback: func(filterId, value) {
        me.reloadData(true, FilterData.new(filterId, value));
    },

    #
    # Replace some too long header text or set "filtered" marker
    #
    # index column
    # string text
    # return string
    #
    getReplaceHeaderText: func(column, text) {
        if ((column == File.INDEX_DATE     and me.filters.isApplied(column)) or
            (column == File.INDEX_AIRCRAFT and me.filters.isApplied(column)) or
            (column == File.INDEX_TYPE     and me.filters.isApplied(column)) or
            (column == File.INDEX_FROM     and me.filters.isApplied(column)) or
            (column == File.INDEX_TO       and me.filters.isApplied(column))
        ) {
            return text ~ " (!)";
        }

        if (column == File.INDEX_LANDINGS) {
            return "Land.";
        }

        if (column == File.INDEX_INSTRUMENT) {
            return "Instr.";
        }

        return text;
    },

    #
    # Draw text
    #
    # hash cGroup - Parent canvas group
    # int x, y - Position of text
    # string text - Text to draw
    # return void
    #
    drawText: func(cGroup, x, y, text) {
        return cGroup.createChild("text")
            .setTranslation(x, y)
            .setColor(me.style.TEXT_COLOR)
            .setText(text);
    },

    #
    # Draw grid with logbook data
    #
    # return void
    #
    reDrawDataContent: func() {
        var y = me.listView.reDrawDataContent();

        # Continue drawing totals row
        me.rowTotal = me.listView.drawHoverBox(y);
        me.drawTotalsRow(me.rowTotal);

        me.listView.dataContent.update();
    },

    #
    # Draw row with totals summary
    #
    # hash cGroup - Parent canvas group
    # return void
    #
    drawTotalsRow: func(cGroup) {
        var x = ListView.PADDING * 2;
        for (var i = 0; i < LogbookDialog.TOTALS_COLUMNS_SHIFT; i += 1) {
            x += me.listView.getX(i);
        }

        me.listView.drawText(cGroup, x, "Totals:");

        for (var i = 0; i < size(me.totals); i += 1) {
            var total = me.totals[i];
            x += me.listView.getX(i + LogbookDialog.TOTALS_COLUMNS_SHIFT);
            me.listView.drawText(cGroup, x, sprintf(LogbookDialog.TOTAL_FORMATS[i], total));
        }
    },

    #
    # Draw bottom bar with buttons
    #
    # return void
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

        me.btnStyle
            .setText(me.getOppositeStyleName())
            .setFixedSize(75, 26)
            .listen("clicked", func { me.toggleStyle(); });

        var btnHelp = canvas.gui.widgets.Button.new(me.group, canvas.style, {})
            .setText("?")
            .setFixedSize(26, 26)
            .listen("clicked", func { me.helpDialog.show(); });

        buttonBox.addStretch(4);
        buttonBox.addItem(btnFirst);
        buttonBox.addItem(btnPrev);
        buttonBox.addStretch(1);
        buttonBox.addItem(me.labelPaging);
        buttonBox.addStretch(1);
        buttonBox.addItem(btnNext);
        buttonBox.addItem(btnLast);
        buttonBox.addStretch(2);
        buttonBox.addItem(me.btnStyle);
        buttonBox.addItem(btnHelp);
        buttonBox.addStretch(1);

        me.vbox.addItem(buttonBox);
    },

    #
    # Toggle style from light to dark and vice versa.
    #
    # return void
    #
    toggleStyle: func() {
        me.style = me.style.NAME == "dark"
            ? me.getStyle().light
            : me.getStyle().dark;

        me.settings.setDarkMode(me.style.NAME == "dark");
        me.settings.save();

        me.toggleBgImage();

        me.canvas.set("background", me.style.CANVAS_BG);
        me.btnStyle.setText(me.getOppositeStyleName());
        me.listView.setStyle(me.style);
        me.filterSelector.setStyle(me.style);

        me.reloadData();

        # TODO: Additional data setting due to crash "non-numeric string in numeric context: 'data'"
        # by dataRows["data"] in ListView, but is it really needed? Will the index still be up to date?
        # if (me.detailsDialog.parentDataIndex != nil) {
        #     me.detailsDialog.listView.setDataToDraw(
        #         me.file.getLogData(me.detailsDialog.parentDataIndex),
        #         me.file.getHeadersData()
        #     );
        # }

        me.detailsDialog.setStyle(me.style);
        me.helpDialog.setStyle(me.style);
    },

    #
    # return string
    #
    getOppositeStyleName: func() {
        return me.style.NAME == "dark"
            ? me.getStyle().light.NAME
            : me.getStyle().dark.NAME;
    },

    #
    # Go to first logbook items
    #
    # return void
    #
    first: func() {
        if (me.startIndex != 0) {
            me.startIndex = 0;
            me.reloadData(false);
        }
    },

    #
    # Go to previous logbook items
    #
    # return void
    #
    prev: func() {
        if (me.startIndex - LogbookDialog.MAX_DATA_ITEMS >= 0) {
            me.startIndex -= LogbookDialog.MAX_DATA_ITEMS;
            me.reloadData(false);
        }
    },

    #
    # Go to next logbook items
    #
    # return void
    #
    next: func() {
        if (me.startIndex + LogbookDialog.MAX_DATA_ITEMS < me.file.getTotalLines()) {
            me.startIndex += LogbookDialog.MAX_DATA_ITEMS;
            me.reloadData(false);
        }
    },

    #
    # Go to last logbook items
    #
    # return void
    #
    last: func() {
        var old = me.startIndex;
        var pages = math.ceil(me.file.getTotalLines() / LogbookDialog.MAX_DATA_ITEMS);
        me.startIndex = (pages * LogbookDialog.MAX_DATA_ITEMS) - LogbookDialog.MAX_DATA_ITEMS;

        if (old != me.startIndex) {
            me.reloadData(false);
        }
    },

    #
    # Reload logbook data
    #
    # bool withHeaders - Set true when headers/filters must be change too.
    # hash filter - FilterData object as {"index": column index, "value": "text"}
    # return void
    #
    reloadData: func(withHeaders = 1, filter = nil) {
        if (filter != nil) {
            # Reset range
            me.startIndex = 0;
            me.filters.applyFilter(filter);
        }

        me.data   = me.file.loadDataRange(me.startIndex, LogbookDialog.MAX_DATA_ITEMS);
        me.totals = me.file.getTotalsData();

        me.listView.setDataToDraw(me.data);

        me.redraw(withHeaders);
        me.setPaging();
    },

    #
    # Redraw windows
    #
    # bool withHeaders - Set true when color must be change too.
    # return void
    #
    redraw: func(withHeaders) {
        if (withHeaders) {
            me.reDrawHeadersContent();
        }
        me.reDrawDataContent();
    },

    #
    # Set paging information
    #
    # return void
    #
    setPaging: func() {
        var curPage = (me.startIndex / LogbookDialog.MAX_DATA_ITEMS) + 1;
        var maxPages = math.ceil(me.file.getTotalLines() / LogbookDialog.MAX_DATA_ITEMS) or 1;
        me.labelPaging.setText(sprintf("%d / %d (%d items)", curPage, maxPages, me.file.getTotalLines()));
    },
};
