/*
 * Peaks demo - browser side.
 *
 * All API calls go to a path relative to this page ("/api/..."), which NGINX
 * reverse-proxies to the Node.js tier (see nginx/peaks.conf). That way the
 * browser only ever talks to the web server: no CORS, no exposed port 3000.
 * To point the page somewhere else instead, define window.PEAKS_API_URL
 * (e.g. "http://10.0.0.5:3000/api/") before this script is loaded.
 */
var url = window.PEAKS_API_URL || '/api/';
var FIELDS = ['rank', 'peak', 'elevation', 'state', 'range'];

$(document).ready(function () {
    $('.show-hide-add-peak').click(function () {
        $('.add-peak-body').toggle('slow');
        $('.show-hide-plus').toggle();
        $('.show-hide-minus').toggle();
    });
    $('#add-data').click(addContent);
    $('#search-data').click(searchData);
    $('#show-all').click(getContent);
    $('#search-text').on('keydown', function (e) {
        if (e.key === 'Enter' || e.which === 13) {
            e.preventDefault();
            searchData();
        }
    });
    getNodeInfo();
    getContent();
});

function getContent() {
    $.ajax(url + 'peaks/', { type: 'GET', dataType: 'json' })
        .done(setContent)
        .fail(function (jqxhr) { showError('load peak data', jqxhr); });
}

function getNodeInfo() {
    $.ajax(url + 'info/', { type: 'GET', dataType: 'json' })
        .done(setInfo)
        .fail(function () {
            $('#nodeInfo').text('Node.js API unreachable at ' + url);
        });
}

function setInfo(data) {
    $('#nodeInfo').empty()
        .append(document.createTextNode('Node.js IP Address: ' + data.ip + ' '))
        .append('<br/>')
        .append(document.createTextNode('Node.js Host Name: ' + data.hostname));
}

function setContent(data) {
    var box = document.getElementById('demobox');
    box.innerHTML = '';
    if (!data || data.length === 0) {
        $(box).append($('<div class="alert alert-info">').text('No peaks found.'));
        return;
    }
    box.appendChild(createTable(data));
}

function createTable(rows) {
    var table = document.createElement('table');
    table.className = 'table table-striped data-table';
    table.id = 'peak-data';

    var thead = document.createElement('thead');
    var tr = document.createElement('tr');
    FIELDS.forEach(function (field) {
        var th = document.createElement('th');
        th.appendChild(document.createTextNode(field.toUpperCase()));
        tr.appendChild(th);
    });
    thead.appendChild(tr);
    table.appendChild(thead);

    var tbody = document.createElement('tbody');
    rows.forEach(function (row) {
        var tr = document.createElement('tr');
        FIELDS.forEach(function (field) {
            var td = document.createElement('td');
            td.appendChild(document.createTextNode(row[field] === undefined ? '' : row[field]));
            tr.appendChild(td);
        });
        tbody.appendChild(tr);
    });
    table.appendChild(tbody);
    return table;
}

function searchData() {
    var searchString = $('#search-text').val().trim();
    var criteria = $('#search-criteria').val();
    if (searchString === '') {
        getContent();
        return;
    }
    $('#demobox').empty();
    $.ajax(url + 'peaks/?' + encodeURIComponent(criteria) + '=' + encodeURIComponent(searchString),
        { type: 'GET', dataType: 'json' })
        .done(setContent)
        .fail(function (jqxhr) { showError('search', jqxhr); });
}

function addContent() {
    var content = {};
    FIELDS.forEach(function (field) {
        content[field] = $('#' + field + '-text').val().trim();
    });
    if (content.peak === '') {
        showError('add peak', null, 'Peak name is required.');
        $('#peak-text').focus();
        return;
    }
    $.ajax(url + 'peaks/', { type: 'POST', data: content, dataType: 'json' })
        .done(function () {
            FIELDS.forEach(function (field) { $('#' + field + '-text').val(''); });
            $('.data-message').stop(true, true).fadeIn(300).delay(3000).fadeOut(300);
            getContent();
        })
        .fail(function (jqxhr) { showError('add peak', jqxhr); });
}

function showError(action, jqxhr, message) {
    var detail = message;
    if (!detail && jqxhr) {
        if (jqxhr.responseJSON && jqxhr.responseJSON.error) {
            detail = jqxhr.responseJSON.error + ' (HTTP ' + jqxhr.status + ')';
        } else if (jqxhr.status === 0) {
            detail = 'could not reach the API at ' + url;
        } else {
            detail = 'HTTP ' + jqxhr.status + ' ' + jqxhr.statusText;
        }
    }
    $('#demobox').empty().append(
        $('<div class="alert alert-danger">').text('Unable to ' + action + ': ' + (detail || 'unknown error'))
    );
}
