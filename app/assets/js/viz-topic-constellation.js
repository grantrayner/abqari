// Topic Constellation — force-directed graph of posts connected by shared tags.
// Loads /visualizations/topic-constellation.json. Each node is a post; links
// connect posts that share at least one tag, with thickness proportional to
// the number of shared tags. Drag to explore; click a node to navigate.
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

    fetch('/visualizations/topic-constellation.json', { cache: 'no-cache' })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (data) { render(data, container, loading, tooltip); })
      .catch(function (e) {
        if (loading) loading.textContent = 'Failed to load: ' + e.message;
      });
  });

  function render(data, container, loading, tooltip) {
    if (loading) loading.style.display = 'none';

    if (!data.nodes || data.nodes.length === 0) {
      container.innerHTML = '<div class="viz-empty"><p>No posts yet — write some posts and tag them to populate the constellation.</p></div>';
      return;
    }

    // Color each node by its first tag for visual grouping. Posts without
    // tags get a neutral grey.
    var tagColor = {};
    var nextColor = 0;
    data.nodes.forEach(function (n) {
      var first = (n.tags || [])[0];
      if (first && !(first in tagColor)) {
        tagColor[first] = PALETTE[nextColor % PALETTE.length];
        nextColor += 1;
      }
    });

    var rect = container.getBoundingClientRect();
    var width = rect.width;
    var height = Math.max(rect.height, 500);

    var svg = d3.select(container)
      .append('svg')
      .attr('viewBox', [-width / 2, -height / 2, width, height])
      .attr('role', 'img')
      .attr('aria-label', 'Topic constellation: ' + data.nodes.length + ' posts connected by shared tags')
      .style('cursor', 'grab');

    var linksLayer = svg.append('g').attr('stroke', 'currentColor').attr('stroke-opacity', 0.3);
    var nodesLayer = svg.append('g');

    // Defensive copies — d3.force mutates these.
    var nodes = data.nodes.map(function (n) { return Object.assign({}, n); });
    var links = data.links.map(function (l) { return Object.assign({}, l); });

    var maxWeight = d3.max(links, function (l) { return l.weight; }) || 1;

    var simulation = d3.forceSimulation(nodes)
      .force('link', d3.forceLink(links).id(function (d) { return d.id; }).distance(70).strength(0.2))
      .force('charge', d3.forceManyBody().strength(-180))
      .force('center', d3.forceCenter(0, 0))
      .force('collide', d3.forceCollide(14));

    var link = linksLayer.selectAll('line').data(links).join('line')
      .attr('stroke-width', function (d) { return Math.max(1, d.weight * 1.5); });

    var node = nodesLayer.selectAll('g').data(nodes).join('g').style('cursor', 'pointer');

    node.append('circle')
      .attr('r', 8)
      .attr('fill', function (d) {
        var first = (d.tags || [])[0];
        return first ? tagColor[first] : '#999';
      })
      .attr('fill-opacity', 0.85)
      .attr('stroke', 'currentColor')
      .attr('stroke-opacity', 0.4)
      .attr('stroke-width', 1.5);

    node.append('text')
      .attr('dx', 12)
      .attr('dy', 4)
      .style('font-size', '11px')
      .style('fill', 'currentColor')
      .style('pointer-events', 'none')
      .text(function (d) { return truncate(d.title, 32); });

    node.on('mouseenter', function (event, d) {
        if (!tooltip) return;
        tooltip.innerHTML = '<strong>' + escapeHtml(d.title) + '</strong>' +
          (d.tags && d.tags.length ? '<br>tags: ' + d.tags.map(escapeHtml).join(', ') : '');
        tooltip.style.display = 'block';
      })
      .on('mousemove', function (event) {
        if (!tooltip) return;
        tooltip.style.left = (event.pageX + 12) + 'px';
        tooltip.style.top = (event.pageY + 12) + 'px';
      })
      .on('mouseleave', function () {
        if (tooltip) tooltip.style.display = 'none';
      })
      .on('click', function (event, d) { window.location = d.id; })
      .call(d3.drag()
        .on('start', function (event, d) {
          if (!event.active) simulation.alphaTarget(0.3).restart();
          d.fx = d.x; d.fy = d.y;
        })
        .on('drag', function (event, d) { d.fx = event.x; d.fy = event.y; })
        .on('end', function (event, d) {
          if (!event.active) simulation.alphaTarget(0);
          d.fx = null; d.fy = null;
        }));

    simulation.on('tick', function () {
      link
        .attr('x1', function (d) { return d.source.x; })
        .attr('y1', function (d) { return d.source.y; })
        .attr('x2', function (d) { return d.target.x; })
        .attr('y2', function (d) { return d.target.y; });
      node.attr('transform', function (d) { return 'translate(' + d.x + ',' + d.y + ')'; });
    });
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function truncate(s, n) {
    s = String(s);
    return s.length <= n ? s : s.slice(0, n - 1) + '…';
  }
})();
