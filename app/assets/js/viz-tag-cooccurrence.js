// Tag Co-occurrence — chord diagram of which tags appear together.
// Loads /visualizations/tag-cooccurrence.json. Each arc on the outer ring
// is a tag; ribbons between arcs show how many posts share both tags.
(function () {
  'use strict';

  var PALETTE = ['#4e79a7', '#f28e2b', '#e15759', '#76b7b2', '#59a14f',
                 '#edc948', '#b07aa1', '#ff9da7', '#9c755f', '#bab0ac',
                 '#d37295', '#fabfd2'];

  document.addEventListener('DOMContentLoaded', function () {
    var container = document.getElementById('viz-container');
    var loading = document.getElementById('viz-loading');
    var tooltip = document.getElementById('viz-tooltip');
    if (!container) return;

    fetch('/visualizations/tag-cooccurrence.json', { cache: 'no-cache' })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (data) { render(data, container, loading, tooltip); })
      .catch(function (e) {
        if (loading) loading.textContent = 'Failed to load: ' + e.message;
      });
  });

  function render(data, container, loading, tooltip) {
    if (loading) loading.style.display = 'none';

    if (!data.tags || data.tags.length < 2) {
      container.innerHTML = '<div class="viz-empty"><p>Need at least two tags with overlap to render a chord diagram.</p></div>';
      return;
    }

    // Filter out tags that never co-occur with anything (otherwise they
    // appear as solo arcs with no ribbons, which is just visual noise).
    var keep = data.tags.map(function (_, i) {
      return data.matrix[i].some(function (v, j) { return v > 0 && i !== j; });
    });
    var tags = data.tags.filter(function (_, i) { return keep[i]; });
    var matrix = data.matrix
      .filter(function (_, i) { return keep[i]; })
      .map(function (row) { return row.filter(function (_, j) { return keep[j]; }); });

    if (tags.length < 2) {
      container.innerHTML = '<div class="viz-empty"><p>No tag co-occurrences yet. Tag posts with multiple tags to see overlap here.</p></div>';
      return;
    }

    var rect = container.getBoundingClientRect();
    var width = rect.width;
    var height = Math.max(rect.height, 500);
    var outerRadius = Math.min(width, height) * 0.5 - 80;
    var innerRadius = outerRadius - 12;

    var svg = d3.select(container)
      .append('svg')
      .attr('viewBox', [-width / 2, -height / 2, width, height])
      .attr('role', 'img')
      .attr('aria-label', 'Chord diagram of ' + tags.length + ' tags');

    var chord = d3.chord().padAngle(0.04).sortSubgroups(d3.descending);
    var chords = chord(matrix);

    var arc = d3.arc().innerRadius(innerRadius).outerRadius(outerRadius);
    var ribbon = d3.ribbon().radius(innerRadius);

    var color = function (i) { return PALETTE[i % PALETTE.length]; };

    // Outer arcs (tags)
    var group = svg.append('g').selectAll('g').data(chords.groups).join('g');

    group.append('path')
      .attr('fill', function (d) { return color(d.index); })
      .attr('stroke', 'currentColor')
      .attr('stroke-opacity', 0.2)
      .attr('d', arc)
      .style('cursor', 'pointer')
      .on('click', function (event, d) {
        window.location = '/tags/' + slugify(tags[d.index]) + '/';
      });

    group.append('text')
      .each(function (d) { d.angle = (d.startAngle + d.endAngle) / 2; })
      .attr('dy', '0.35em')
      .attr('transform', function (d) {
        return 'rotate(' + (d.angle * 180 / Math.PI - 90) + ') ' +
               'translate(' + (outerRadius + 8) + ') ' +
               (d.angle > Math.PI ? 'rotate(180)' : '');
      })
      .attr('text-anchor', function (d) { return d.angle > Math.PI ? 'end' : 'start'; })
      .style('font-size', '11px')
      .style('fill', 'currentColor')
      .text(function (d) { return tags[d.index]; });

    // Inner ribbons (co-occurrences)
    svg.append('g').attr('fill-opacity', 0.6)
      .selectAll('path').data(chords).join('path')
      .attr('d', ribbon)
      .attr('fill', function (d) { return color(d.source.index); })
      .attr('stroke', 'currentColor')
      .attr('stroke-opacity', 0.15)
      .on('mouseenter', function (event, d) {
        if (!tooltip) return;
        tooltip.innerHTML = '<strong>' + escapeHtml(tags[d.source.index]) +
                            '</strong> ↔ <strong>' + escapeHtml(tags[d.target.index]) + '</strong><br>' +
                            d.source.value + ' shared post' + (d.source.value === 1 ? '' : 's');
        tooltip.style.display = 'block';
      })
      .on('mousemove', function (event) {
        if (!tooltip) return;
        tooltip.style.left = (event.pageX + 12) + 'px';
        tooltip.style.top = (event.pageY + 12) + 'px';
      })
      .on('mouseleave', function () { if (tooltip) tooltip.style.display = 'none'; });
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function slugify(s) {
    return String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  }
})();
